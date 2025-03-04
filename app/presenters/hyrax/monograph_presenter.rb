# frozen_string_literal: true

module Hyrax
  class MonographPresenter < WorkShowPresenter # rubocop:disable Metrics/ClassLength
    include CommonWorkPresenter
    include CitableLinkPresenter
    include EditionPresenter
    include EpubAccessibilityMetadataPresenter
    include FeaturedRepresentatives::MonographPresenter
    include OpenUrlPresenter
    include SocialShareWidgetPresenter
    include TitlePresenter
    include TombstonePresenter
    include ActionView::Helpers::UrlHelper
    include Skylight::Helpers

    delegate :date_modified, :date_uploaded, :location, :description,
             :creator_display, :creator_full_name, :contributor, :content_warning, :content_warning_information,
             :subject, :section_titles, :based_near, :publisher, :date_published, :language,
             :isbn, :license, :rightsholder, :open_access, :funder, :funder_display, :holding_contact, :has_model,
             :buy_url, :embargo_release_date, :lease_expiration_date, :rights, :series,
             :visibility, :identifier, :doi, :handle, :thumbnail_path, :previous_edition, :next_edition,
             :volume, :oclc_owi, :copyright_year, :award,
             to: :solr_document

    def creator # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      # this is the value used in CitationsBehavior, so remove anything after the second comma in a name, like HEB's...
      # author birth/death years etc
      citable_creators = []
      solr_document.creator&.each do |creator|
        citable_creator = creator&.split(',')&.map(&:strip)&.first(2)&.join(', ')
        citable_creators << citable_creator if citable_creator.present?
      end
      citable_creators
    end

    def citations_ready?
      # everything used by Hyrax::CitationsBehavior
      title.present? && creator.present? && location.present? &&
        date_created.first.present? && publisher.first.present?
    end

    def based_near_label
      # wrap this in an array as CitationsBehavior seems to be calling `.first` on it
      Array(location)
    end

    instrument_method
    def ordered_section_titles
      return @section_titles if @section_titles.present?

      # See HELIO-4771. This query won't run at all unless the custom_section_facet partial is displayed, which uses...
      # reorder_section_facet() from FacetsHelper, which in turn calls this method.
      @section_titles = section_titles.presence ||
        ActiveFedora::SolrService.query("+has_model_ssim:FileSet AND +monograph_id_ssim:#{id}",
                                        sort: 'monograph_position_isi asc', fl: [:section_title_tesim],
                                        rows: 100_000).map { |doc| doc['section_title_tesim'] }.flatten.uniq.reject(&:blank?)
    end

    def display_section_titles(section_titles_in)
      section_titles_out = []
      ordered_section_titles.each do |ordered_title|
        section_titles_in.each { |title| section_titles_out << ordered_title if title == ordered_title }
      end
      section_titles_out.blank? ? section_titles_in.to_sentence : section_titles_out.to_sentence
    end

    def creator_display?
      solr_document.creator_display.present?
    end

    def rightsholder?
      solr_document.rightsholder.present?
    end

    def copyright_year?
      solr_document.copyright_year.present?
    end

    def holding_contact?
      solr_document.holding_contact.present?
    end

    def publisher?
      solr_document.publisher.present?
    end

    def open_access?
      open_access&.casecmp('yes')&.zero? || false
    end

    def funder?
      solr_document.funder.present?
    end

    def funder_display?
      solr_document.funder_display.present?
    end

    def date_created
      # Only show the first 4 contiguous digits of this, which is the citation publication date, because...
      # for sorting we also allow `-MM-DD` and, in theory, other digits appended (see MonographIndexer)
      # optionally take a 'c' right next to that, as almost 3000 HEB titles have stuff like c1996 in here
      #
      # wrap this in an array as CitationsBehavior calls `.first` on it, though since we first started using...
      # CitationsBehavior we have copied pretty much all of it into heliotrope so could change that if we wanted to
      Array(solr_document['date_created_tesim']&.first.to_s[/c?[0-9]{4}/])
    end

    def date_created?
      date_created.present?
    end

    def isbn_noformat
      isbns = []
      isbn.each do |isbn|
        isbn_removeformat = isbn.sub(/\(.+\)/, '').strip
        isbns << isbn_removeformat if isbn_removeformat.present?
      end
      isbns
    end

    def awards
      awards = []
      award.each do |award|
        # each one should look something like this:
        # 2022|Book of the Year|American Library Association
        # and we'll display it like this in Fedora:
        # 2022 Book of the Year (American Library Association)
        award_components = award.split('|')
        next unless award_components.count == 3
        awards << "#{award_components[0].strip} #{award_components[1].strip} (#{award_components[2].strip})"
      end
      return nil if awards.blank?
      awards.sort.join("\n")
    end

    def bar_number
      identifier&.find { |i| i[/^bar_number:.*/] }&.gsub('bar_number:', '')&.strip
    end

    def prepare_display_names(comma_separated_names, author_type, orcids)
      forward_names = []
      comma_separated_names.each_with_index { |val, index| forward_names << unreverse_name(val) + (orcids ? maybe_add_orcid(index, author_type) : '') }
      forward_names
    end

    def maybe_add_orcid(index, author_type)
      key = "#{author_type}_orcids_ssim"
      if solr_document[key].present? && solr_document[key][index].present?
        # https://info.orcid.org/brand-guidelines/#Inline_ORCID_iD
        "<sup><a target=\"_blank\" href=\"#{solr_document[key][index]}\">#{ActionController::Base.helpers.image_tag('orcid_16x16.gif', alt: 'ORCID page', width: '16px', height: '16px')}</a></sup>"
      else
        ''
      end
    end

    def unreverse_name(comma_separated_name)
      comma_separated_name.split(',').map(&:strip).reverse.join(' ')
    end

    def authors(contributors: true, orcids: false)
      return creator_display if creator_display?
      authorship_names = if contributors
                           [prepare_display_names(solr_document.creator, :creator, orcids), prepare_display_names(contributor, :contributor, orcids)]
                         else
                           [prepare_display_names(solr_document.creator, :creator, orcids)]
                         end
      authorship_names.flatten.to_sentence(last_word_connector: ' and ')
    end

    def creator_orcids
      solr_document['creator_orcids_ssim']
    end

    def subdomain
      Array(solr_document['press_tesim']).first
    end

    def press
      Array(solr_document['press_name_ssim']).first
    end

    def monograph_tombstone_message
      monograph = Sighrax.from_presenter(self)
      monograph.tombstone_message ||
        monograph.publisher.tombstone_message ||
          Sighrax.platform.tombstone_message(monograph.publisher.name)
    end

    def buy_url?
      solr_document.buy_url.present?
    end

    def buy_url
      solr_document.buy_url.first if buy_url?
    end

    def description?
      solr_document.description.present?
    end

    def catalog_url(share_link = nil)
      if share_link.present?
        Rails.application.routes.url_helpers.monograph_catalog_path(id, share: share_link)
      else
        Rails.application.routes.url_helpers.monograph_catalog_path(id)
      end
    end

    def monograph_coins_title?
      return false unless defined? monograph_coins_title
      monograph_coins_title.present?
    end

    def creators_with_roles
      # Wherein we hopelessly try to make structure out of an unstructured string
      # Used for sending XML to crossref to make DOIs
      creators = []
      return creators if solr_document["creator_tesim"].blank?

      solr_document["creator_tesim"].first.split(/\r\n?|\n/).reject(&:blank?).each do |creator|
        # Last, First (Role)
        creator.match(/(.*?),(.*?)\((.*?)\)$/) do |m|
          creators << OpenStruct.new(lastname: m[1].strip, firstname: m[2].strip, role: m[3])
        end && next
        # Last, First
        creator.match(/(.*?),(.*?)$/) do |m|
          creators << OpenStruct.new(lastname: m[1].strip, firstname: m[2].strip, role: "author")
        end && next
        # Last
        creator.match(/(.*?)$/) do |m|
          creators << OpenStruct.new(lastname: m[1].strip, firstname: "", role: "author")
        end && next
      end
      creators
    end

    # HELIO-3346, HELIO-3347: Support for indicators to help users understand
    # what books they have access to and why.
    #
    # @param [Array] allow_product_ids {  current_actor.products.pluck(:id) }
    # @param [Array] allow_read_product_ids {  Sighrax.allow_read_products.pluck(:id) }
    instrument_method
    def access_level(actor_product_ids, allow_read_product_ids) # rubocop:disable Metrics/PerceivedComplexity
      # Open Access
      return access_indicators(:open_access)  if /yes/i.match?(solr_document.open_access)
      # Unknown because monograph needs to be reindexed!
      return access_indicators(:unknown)      unless solr_document['products_lsim']
      # Purchased
      return access_indicators(:purchased)    if actor_product_ids && (solr_document['products_lsim'] & actor_product_ids).any?
      # Free
      return access_indicators(:free)         if allow_read_product_ids && (solr_document['products_lsim'] & allow_read_product_ids).any?
      # Unrestricted
      return access_indicators(:unrestricted) if solr_document['products_lsim'].include?(0)
      # Restricted
      access_indicators(:restricted)
    end

    instrument_method
    def access_indicators(level)
      case level
      when :open_access
        OpenStruct.new(level:   :open_access,
                       show?:   true,
                       icon_sm: ActionController::Base.helpers.image_tag("open-access.svg", width: "16px", height: "16px", alt: "Open Access"),
                       icon_lg: ActionController::Base.helpers.image_tag("open-access.svg", width: "24px", height: "24px", alt: "Open Access"),
                       text:    ::I18n.t('access_levels.access_level_text.open_access'))
      when :purchased
        OpenStruct.new(level:   :purchased,
                       show?:   true,
                       icon_sm: ActionController::Base.helpers.image_tag("green_check.svg", width: "16px", height: "16px", alt: "Purchased"),
                       icon_lg: ActionController::Base.helpers.image_tag("green_check.svg", width: "24px", height: "24px", alt: "Purchased"),
                       text:    ::I18n.t('access_levels.access_level_text.purchased'))
      when :free
        OpenStruct.new(level:   :free,
                       show?:   true,
                       icon_sm: ActionController::Base.helpers.image_tag("free.svg", width: "38px", height: "16px", alt: "Free", style: "vertical-align: top"),
                       icon_lg: ActionController::Base.helpers.image_tag("free.svg", width: "57px", height: "24px", alt: "Free", style: "vertical-align: bottom"),
                       text:    ::I18n.t('access_levels.access_level_text.free'))
      when :unrestricted
        # "unrestricted" is a Monograph with no Component. The products_lsim field
        # is indexed with a 0. As opposed to "unknown" which has an empty products_lsim
        # field which means the monograph should be reindexed
        OpenStruct.new(level:   :unrestricted,
                       show?:   false,
                       icon_sm: '',
                       icon_lg: '',
                       text:    '')
      when :restricted
        access_options_link = if reader_ebook_id.present?
                                " " + link_to(::I18n.t('access_levels.access_level_text.restricted_access_options'), Rails.application.routes.url_helpers.monograph_authentication_url(id: id))
                              else
                                ''
                              end
        OpenStruct.new(level:   :restricted,
                       show?:   true,
                       icon_sm: ActionController::Base.helpers.image_tag("lock_locked.svg", width: "16px", height: "16px", alt: "Restricted"),
                       icon_lg: ActionController::Base.helpers.image_tag("lock_locked.svg", width: "24px", height: "24px", alt: "Restricted"),
                       text:    ::I18n.t('access_levels.access_level_text.restricted') + access_options_link)
      else
        OpenStruct.new(level:   :unknown,
                       show?:   false,
                       icon_sm: '',
                       icon_lg: '',
                       text:    '')
      end
    end
  end
end
