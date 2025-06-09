# frozen_string_literal: true

# HELIO-2819

module Royalty
  class UsageReport
    include Royalty::Reportable
    include ActionView::Helpers::NumberHelper

    def initialize(subdomain, start_date, end_date)
      @subdomain = subdomain
      @press = Press.where(subdomain: @subdomain).first
      @start_date = Date.parse(start_date)
      @end_date = Date.parse(end_date)
    end

    def report
      items = item_report[:items]

      items = update_results(items)
      items = remove_extra_lines(items)
      @total_hits_all_rightsholders = total_hits_all_rightsholders(items)
      # now that the math is done, format numbers
      items = format_hits(items)
      # HELIO-3572
      items = add_hebids(items)
      items = reclassify_isbns(items)
      # HELIO-4886 Metric_Type changed from "Total_Item_Requests" to the made-up "Total_Title_Requests"
      items = total_item_to_title(items)
      # create and sent reports
      reports = copyholder_reports(items)
      reports = combined_report(reports, items)
      send_reports("fulcrum_royalty_usage_reports", reports)
      reports
    end

    # HELIO-3720
    # Returns a report (not csv) for a given rightsholder
    def report_for_copyholder(rightsholder)
      # this is not efficient, just using what's already here to get this working
      items = item_report[:items]
      ids = rightsholders.to_a.filter_map { |i| i[0] if i[1] == rightsholder }
      items = items.filter_map { |item| item if item["Parent_Proprietary_ID"].in?(ids) }

      items = update_results(items)
      items = remove_extra_lines(items)
      @total_hits_all_rightsholders = total_hits_all_rightsholders(items)
      items = format_hits(items)
      items = add_hebids(items)
      items = reclassify_isbns(items)

      {
        header: {
          "Collection Name": @press.name,
          "Report Name": "Royalty Usage Report",
          "Rightsholder Name": rightsholder,
          "Reporting Period": "#{@start_date.strftime("%Y%m")} to #{@end_date.strftime("%Y%m")}",
          "Total Hits": number_with_delimiter(@total_hits_all_rightsholders),
        },
        items: items
      }
    end

    private

      # Generate one additional summary usage report for all rightsholders
      def combined_report(reports, all_items)
        all_items = add_rightsholder_to_combined_report(all_items)
        combined = "usage_combined.#{@start_date.strftime("%Y%m")}-#{@end_date.strftime("%Y%m")}.csv"
        reports[combined] = {
          header: {
            "Collection Name": @press.name,
            "Report Name": "Royalty Usage Summary Report",
            "Rightsholder Name": "All Rights Holders",
            "Reporting Period": "#{@start_date.strftime("%Y%m")} to #{@end_date.strftime("%Y%m")}",
            "Total Hits (All Titles, All Rights Holders)": number_with_delimiter(@total_hits_all_rightsholders),
          },
          items: all_items
        }
        reports
      end

      def copyholder_reports(all_items)
        reports = {}
        items_by_copyholders(all_items).each do |copyholder, items|
          name = copyholder.gsub(/[^0-9A-z.\-]/, '_') + ".usage.#{@start_date.strftime("%Y%m")}-#{@end_date.strftime("%Y%m")}.csv"
          reports[name] = {
            header: {
              "Collection Name": @press.name,
              "Report Name": "Royalty Usage Report",
              "Rightsholder Name": copyholder,
              "Reporting Period": "#{@start_date.strftime("%Y%m")} to #{@end_date.strftime("%Y%m")}",
              # Total Hits (All Rights Holders): [total of all Total Item Requests for all content types, regardless of rightsholder, for the period]
              "Total Hits (All Titles, All Rights Holders)": number_with_delimiter(@total_hits_all_rightsholders),
            },
            items: items
          }
        end
        reports
      end

      def total_item_to_title(items)
        # HELIO-4886 Metric_Type value changed from "Total_Item_Requests" to the made-up "Total_Title_Requests"
        # We know that there's no such thing as a "Total_Title_Requests" metric type in COUNTER 5 and 5.1 but we're doing this anyway.
        items.filter_map { |item| item["Metric_Type"] = "Total_Title_Requests" }
        items
      end

      def remove_extra_lines(items)
        # When a COUNTER5 Item Report is created with both OA_Gold *and* Controlled access_types,
        # there is one entire row for OA_Gold and one entire row for Controlled for each item. Since a book is
        # always either OA_Gold *OR* Controlled, one of these rows is empty: it has no hits/Reporting_Period_Total
        # It's weird and confusing, but that's how it works in COUNTER5.
        # For these reports though, we're going to remove the "extra" row, either OA
        # or Controlled, if the row has no Hits. It will make the resulting report easier to read, probably.
        items.filter_map { |item| item["Hits"] == 0 ? nil : item }
      end

      def update_results(items)
        items.each do |item|
          # Reporting_Period_Total:
          # Change label to Hits
          item.transform_keys! { |k| k == "Reporting_Period_Total" ? "Hits" : k }
          # Access_Type: modify the values as follows:
          # OA_Gold -> OA
          # (Controlled can remain Controlled)
          item["Access_Type"] = "OA" if item["Access_Type"] == "OA_Gold"
        end

        items
      end

      def params
        CounterReporter::ReportParams.new('ir', {
          institution: "*",
          start_date: @start_date.to_s,
          end_date: @end_date.to_s,
          press: @press.id,
          metric_type: 'Total_Item_Requests',
          data_type: 'Book',
          access_type: ['Controlled', 'OA_Gold'],
          access_method: 'Regular',
          attributes_to_show: ["Authors", "Publication_Date", "Data_Type", "YOP", "Access_Type", "Access_Method"],
          include_parent_details: "true",
          exclude_monthly_details: "false",
          include_monthly_details: "true"
        })
      end
  end
end
