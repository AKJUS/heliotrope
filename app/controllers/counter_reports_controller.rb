# frozen_string_literal: true

class CounterReportsController < ApplicationController
  before_action :wayfless_redirect_to_shib_login, only: %i[index]
  before_action :set_counter_report_service, only: %i[index show edit update]
  before_action :set_counter_report, only: %i[show]
  before_action :set_presses_and_institutions, only: %i[index show]

  def customers
    @customers = if Sighrax.platform_admin?(current_actor)
                   Greensub::Institution.order(:name)
                 elsif current_actor.press_role?
                   Greensub::Institution.order(:name)
                 else
                   current_institutions.sort_by(&:name)
                 end
    redirect_to counter_report_customer_platforms_path(customer_id: @customers.first.id) if @customers.count == 1
  end

  def platforms
    @customer = Greensub::Institution.find(params[:customer_id])
    @platforms = if Sighrax.platform_admin?(current_actor)
                   Press.order(:name)
                 elsif current_actor.press_role?
                   current_actor.presses.order(:name)
                 else
                   Press.order(:name)
                 end
    redirect_to counter_report_customer_platform_reports_path(customer_id: @customer.id, platform_id: @platforms.first.id) if @platforms.count == 1
  end

  def index
    return render if @counter_report_service.present?

    config = Rails.root.join('config', 'scholarlyiq.yml')
    if Flipflop.scholarlyiq_counter_redirect? && File.exist?(config)
      redirect_to ScholarlyiqRedirectUrlService.encrypted_url(config, @institutions)
    else
      render 'counter_reports/without_customer_id/index'
    end
  end

  def edit
    @customer = Greensub::Institution.find(params[:customer_id])
    @platform = Press.find(params[:platform_id])
    @report = params[:id].downcase.to_sym
    @title = CounterReport::COUNTER_REPORT_TITLE[@report]
  end

  def update
    respond_to do |format|
      format.html { redirect_to counter_report_customer_platform_report_path(params[:customer_id], params[:platform_id], params[:id]), notice: 'COUNTER Report was successfully created.' }
    end
  end

  def show # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return render if @counter_report_service.present?

    # institutional 'guest' users can only see their institutions, but all presses
    # press admins can only see their presses, but all institutions
    unless authorized_insitutions_or_presses?
      @skip_footer = true
      render 'counter_reports/unauthorized', status: :unauthorized
    end

    case params[:id]
    when 'pr'
      @report = CounterReporterService.pr(params)
    when 'pr_p1'
      @report = CounterReporterService.pr_p1(params)
    when 'tr'
      @report = CounterReporterService.tr(params)
    when 'tr_b1'
      @report = CounterReporterService.tr_b1(params)
    when 'tr_b2'
      @report = CounterReporterService.tr_b2(params)
    when 'tr_b3'
      @report = CounterReporterService.tr_b3(params)
    when 'ir'
      @report = CounterReporterService.ir(params)
    when 'ir_m1'
      @report = CounterReporterService.ir_m1(params)
    when 'counter4_br2'
      # only csv for this report
      @report = CounterReporterService.counter4_br2(params)
      send_data @report, filename: "Fulcrum_COUNTER4_BR2_#{Time.zone.today.strftime('%Y-%m-%d')}.csv"
      return
    end

    if params[:csv]
      send_data CounterReporterService.csv(@report), filename: "Fulcrum_#{@title.gsub(/\s/, '_')}_#{Time.zone.today.strftime('%Y-%m-%d')}.csv"
    else
      render 'counter_reports/without_customer_id/show'
    end
  end

  private

    def authorized_insitutions_or_presses?
      return false unless @institutions.map(&:identifier).include?(params[:institution])
      return false if @presses.present? && @presses.map(&:id).exclude?(params[:press].to_i)

      true
    end

    def set_counter_report_service
      @counter_report_service = CounterReportService.new(params[:customer_id], params[:platform_id], current_actor) if params[:customer_id].present? && params[:platform_id].present?
    end

    def set_counter_report
      @title = CounterReport::COUNTER_REPORT_TITLE[params[:id]&.downcase&.to_sym]
      @counter_report = @counter_report_service.report(params[:id]) if @counter_report_service.present?
    end

    def set_presses_and_institutions
      return if @counter_report_service.present?

      @institutions = current_institutions.sort_by(&:name)
      @presses = Press.order(:name)
      if @institutions.empty? || @presses.empty?
        @skip_footer = true
        render 'counter_reports/unauthorized', status: :unauthorized
      end
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def counter_report_params
      params.require(:counter_report).permit
      params.permit(:institution, :press, :start_date, :end_date, :metric_type, :access_type, :access_method, :data_type, :yop)
    end
end
