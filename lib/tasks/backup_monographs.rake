# frozen_string_literal: true

desc 'Task to backup all Monograph files and metadata to individual NOID-named tar archives'
namespace :heliotrope do
  task :backup_monographs, [:backup_directory, :refresh_all_backups] => :environment do |_t, args|
    # Normal usage:
    # bundle exec rails "heliotrope:backup_monographs[/path/to/backup_directory]"
    # Force refresh of all backups:
    # bundle exec rails "heliotrope:backup_monographs[/path/to/backup_directory, true]"

    unless File.writable?(args.backup_directory)
      message = "The backup directory for Monographs is not writable: #{args.backup_directory}"

      if Settings.host == "www.fulcrum.org"
        ActionMailer::Base.mail(to: 'fulcrum-dev@umich.edu',
                                from: 'fulcrum-dev@umich.edu',
                                subject: 'Fulcrum Monographs Backup Task Failed',
                                body: message).deliver_now
      end

      fail message
    end

    count = 0
    docs = monograph_docs

    docs.each do |monograph_doc|
      output_tar_file_path = File.join(args.backup_directory, monograph_doc['press_tesim']&.first, "#{monograph_doc.id}.tar")

      if args.refresh_all_backups || !deposit_up_to_date?(monograph_doc, output_tar_file_path)
        Dir.mktmpdir(["backup-monograph-#{monograph_doc.id}-"], File.join(Settings.scratch_space_path)) do |temp_directory|
          # to prevent absolute paths being stored in the archive we'll `cd` to the temp folder...
          Dir.chdir(temp_directory) do
            # ...and export into a NOID-named folder inside that.
            temporary_noid_directory = File.join(temp_directory, monograph_doc.id)
            FileUtils.mkdir_p(temporary_noid_directory)
            Export::Exporter.new(monograph_doc.id).extract(File.join(temporary_noid_directory), true)

            output_press_directory = File.dirname(output_tar_file_path)
            FileUtils.mkdir_p(output_press_directory) unless Dir.exist?(output_press_directory)
            # note we're using the relative NOID path here so the tar won't contain absolute paths
            Minitar.pack(monograph_doc.id, output_tar_file_path, 'wb')

            count += 1
          end
        end
      else
        next
      end
    end
    puts "Backed up #{count} Monographs"

    # Now that recently created/modified Monographs are backed up, we'll run a quick loop to see if any existing...
    # backed-up Monographs have been deleted from Fulcrum. If so, we'll just mark their tar files with a name change...
    # so that they can be easily skipped over when restoring content.
    count = 0
    existing_monograph_ids = docs&.map { |doc| doc.id }
    backup_file_paths = Dir.glob(File.join(args.backup_directory, '**/*.tar')).sort

    backup_file_paths.each do |backup_file|
      monograph_id = File.basename(backup_file, '.tar')
      if existing_monograph_ids.exclude?(monograph_id)
        # Fedora sanity check, confirm that it's not just missing from Solr before renaming the tar file
        begin
          Monograph.find(monograph_id)
        rescue Ldp::Gone
          count += 1
          File.rename(backup_file, backup_file + '.deleted')
        end
      end
    end
    puts "Marked #{count} Monographs as deleted"
  end
end

def monograph_docs
  ActiveFedora::SolrService.query(
    "+has_model_ssim:Monograph",
    fl: %w[id date_modified_dtsi press_tesim],
    rows: 100_000
  ) || []
end

def file_set_docs(monograph_doc)
  ActiveFedora::SolrService.query(
    "+has_model_ssim:FileSet AND +monograph_id_ssim:#{monograph_doc.id}",
    fl: %w[date_modified_dtsi],
    rows: 100_000
  ) || []
end

def deposit_up_to_date?(monograph_doc, tar_file_path)
  return false unless File.exist?(tar_file_path)

  last_backup_timestamp = File.mtime(tar_file_path)

  return false if Time.zone.parse(monograph_doc['date_modified_dtsi'].to_s) > last_backup_timestamp

  file_set_docs(monograph_doc).each do |file_set_doc|
    return false if Time.zone.parse(file_set_doc['date_modified_dtsi'].to_s) > last_backup_timestamp
  end

  true
end
