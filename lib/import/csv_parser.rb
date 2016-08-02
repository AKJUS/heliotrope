module Import
  class CSVParser
    attr_reader :file

    def initialize(input_file)
      @file = input_file
    end

    def attributes(errors_out = '')
      attrs = {}
      errors = ''
      # a CSV can only have one monograph (probably for in-house use only)...
      attrs['monograph'] = {}
      attrs['monograph']['files'] = []
      attrs['monograph']['files_metadata'] = []
      # ... but can have many sections
      attrs['sections'] = {}

      puts "Parsing file: #{file}"
      rows = CSV.read(file, headers: true, skip_blanks: true).delete_if { |row| row.to_hash.values.all?(&:blank?) }
      row_data = RowData.new

      # human-readable row counter
      row_num = rows.count

      # The template CSV file contains an extra row after the
      # headers that has explanatory text about how to fill in
      # the table.  We want to throw away that text.
      rows.delete(0)

      errors = ''

      # reverse_each is a workaround for default order of the assets (created time)
      rows.reverse_each do |row|
        row.each { |_, value| value.strip! if value }

        if missing_file_name?(row)
          puts "Row #{row_num}: File name missing - skipping row!"
          row_num -= 1
          next
        end

        if asset_data?(row)
          file_attrs = {}
          errors += row_data.data_for_asset(row_num, row, file_attrs)
          attach_asset(row, attrs, file_attrs)
        else
          row_data.data_for_monograph(row, attrs['monograph'])
        end
        row_num -= 1
      end
      errors_out.replace errors
      attrs
    end

    private

      def missing_file_name?(row)
        row['File Name'].blank?
      end

      def asset_data?(row)
        row['File Name'] != '://:MONOGRAPH://:' && row['Section'] != '://:MONOGRAPH://:'
      end

      def attach_asset(row, attrs, file_attrs)
        # blank section will mean 'attach to monograph'
        # puts file_attrs.to_s

        section_title = if row['Section']
                          row['Section']
                        else
                          '://:MONOGRAPH://:'
                        end

        # using parallel arrays for files and their metadata
        # for both monographs and sections
        if section_title != '://:MONOGRAPH://:'
          # create section if new
          unless attrs['sections'][section_title]
            current_section = {}
            current_section['title'] = Array(row['Section'].split(';')).map(&:strip)
            current_section['files'] = []
            current_section['files_metadata'] = []
            attrs['sections'][section_title] = current_section
          end
          attrs['sections'][section_title]['files'] << row['File Name']
          attrs['sections'][section_title]['files_metadata'] << file_attrs
          # puts "    ... will attach to Section: #{section_title}"
        else
          # An array of file names with a matching array of
          # metadata for each of those files.
          attrs['monograph']['files'] << row['File Name']
          attrs['monograph']['files_metadata'] << file_attrs
          # puts "    ... will attach directly to monograph"
        end

        # TODO: The matching arrays will only work if they
        # both contain exactly the same number of elements.
        # We should either store the file name together with
        # the metadata, or else raise an error if the 2 arrays
        # don't have the same count.
      end
  end
end
