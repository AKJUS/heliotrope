# frozen_string_literal: true

module CommonWorkPresenter
  extend ActiveSupport::Concern
  include Skylight::Helpers

  def thumbnail_tag(width, options = {})
    options['style'] = "filter: grayscale(1)" if respond_to?(:tombstone?) && tombstone?
    if representative_id.present?
      ActionController::Base.helpers.image_tag(Riiif::Engine.routes.url_helpers.image_path(cache_buster_id, "#{width},", format: "png"), options)
    else
      options[:style] = "max-width: #{width}px"
      ActionController::Base.helpers.image_tag(thumbnail_path || '', options)
    end
  end

  def poster_tag(options = {})
    options['style'] = "filter: grayscale(1)" if respond_to?(:tombstone?) && tombstone?
    if representative_id.present?
      ActionController::Base.helpers.image_tag(Riiif::Engine.routes.url_helpers.image_path(cache_buster_id, :full, :full, 0, format: "png"), options)
    else
      ActionController::Base.helpers.image_tag(thumbnail_path || '', options)
    end
  end

  def cache_buster_id
    thumbnail = Hyrax::DerivativePath.new(representative_id).derivative_path + "thumbnail.jpeg"
    return representative_id unless File.exist? thumbnail
    representative_id + "#{File.mtime(thumbnail).to_i}"
  end

  # This overrides CC 1.6.2's work_show_presenter.rb which is recursive.
  # Because our FileSets also have respresentative_presenters (I guess that's not normal?)
  # this recursive call from Work -> Arbitrary Nesting of Works -> FileSet never ends.
  # Our PCDM model currently only has Work -> FileSet so this this non-recursive approach should be fine
  # 2020-03-31: Use this sparingly, if at all. We don't want to go to solr for each FileSet unless it's
  # absolutly neccessary. On press_catalog pages for instance this can cause N +1 problems, see HELIO-3305
  def representative_presenter
    return nil if representative_id.blank?
    @representative_presenter ||= Hyrax::PresenterFactory.build_for(ids: [representative_id], presenter_class: Hyrax::FileSetPresenter, presenter_args: current_ability).first
  end

  def license?
    solr_document.license.present? && solr_document.license.first.present?
  end

  def license_alt_text
    return 'Creative Commons License' unless license?
    # account for any (unexpected) mix of http/https links in config/authorities/licenses.yml
    link_content = solr_document.license.first.sub('http:', 'https:')
    # in-house outlier "All Rights Reserved" value, no icon
    return 'All Rights Reserved' if link_content == 'https://www.press.umich.edu/about/licenses#all-rights-reserved'

    # get term for use as alt text
    term = Hyrax::LicenseService.new.select_all_options.find { |a| a[1] == link_content }&.first
    term || 'Creative Commons License'
  end

  def license_link_content
    return 'Creative Commons License' unless license?
    # account for any (unexpected) mix of http/https links in config/authorities/licenses.yml
    link_content = solr_document.license.first.sub('http:', 'https:')
    # in-house outlier "All Rights Reserved" value, no icon
    return 'All Rights Reserved' if link_content == 'https://www.press.umich.edu/about/licenses#all-rights-reserved'

    # get term for use as alt text
    term = Hyrax::LicenseService.new.select_all_options.find { |a| a[1] == link_content }&.first
    term ||= 'Creative Commons License'

    link_content = link_content.sub('licenses', 'l')
    link_content = link_content.sub('publicdomain', 'p')
    link_content = link_content.sub('https://creativecommons', 'https://i.creativecommons') + '80x15.png'
    link_content = '<img alt="' + term + '" style="border-width:0" src="' + link_content + '"/>'
    link_content.html_safe # rubocop:disable Rails/OutputSafety
  end
end
