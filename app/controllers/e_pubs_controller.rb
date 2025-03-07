# frozen_string_literal: true

class EPubsController < CheckpointController
  include Watermark::Watermarkable
  include IrusAnalytics::Controller::AnalyticsBehaviour

  protect_from_forgery except: :file
  before_action :setup
  before_action :wayfless_redirect_to_shib_login, only: %i[show]

  def show # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @parent_noid = @parent_presenter.id

    unless @policy.show?
      CounterService.new(self, @presenter).count(request: 1, turnaway: "No_License") unless @parent_presenter.tombstone?
      return redirect_to monograph_authentication_url(@parent_noid)
    end

    @actor_product_ids = current_actor.products.pluck(:id)
    @allow_read_product_ids = Sighrax.allow_read_products.pluck(:id)

    @title = @parent_presenter.present? ? @parent_presenter.page_title : @presenter.page_title
    @citable_link = @parent_presenter.citable_link
    @subdomain = @presenter.parent.subdomain

    @ebook_download_presenter = EBookDownloadPresenter.new(@parent_presenter, current_ability, current_actor)

    @search_url = main_app.epub_search_url(@noid, q: '').gsub!(/locale=en&/, '') if @entity.is_a?(Sighrax::EpubEbook)

    @press = Press.where(subdomain: @subdomain).first
    @component = component

    CounterService.from(self, @presenter).count(request: 1)
    send_irus_analytics_request

    log_share_link_use

    if @entity.is_a?(Sighrax::EpubEbook)
      render layout: false
    elsif @entity.is_a?(Sighrax::PdfEbook)
      render 'e_pubs/show_pdf', layout: false
    else
      head :not_found
    end
  end

  # HELIO-4143, HELIO-3778
  def item_identifier_for_irus_analytics
    CatalogController.blacklight_config.oai[:provider][:record_prefix] + ":" + @presenter.parent.id
  end

  def file # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return head :no_content unless @policy.show?

    if @entity.is_a?(Sighrax::EpubEbook)
      epub = EPub::Publication.from_directory(UnpackService.root_path_from_noid(@noid, 'epub'))
      filename = params[:file] + '.' + params[:format]

      file = epub.file(filename)
      file = file.to_s.sub(/releases\/\d+/, "current")
      response.headers['X-Sendfile'] = file

      send_file file
    elsif @entity.is_a?(Sighrax::PdfEbook)
      pdf = UnpackService.root_path_from_noid(@noid, 'pdf_ebook') + ".pdf"
      if File.exist? pdf
        # HELIO-4444 never cache 206 Range requests as it makes Chromium browsers act weird over EZproxy
        # The NOID part of the conditional is to allow the OCLC folks to continue their testing (HELIO-4448)
        response.headers['Cache-Control'] = 'no-cache, no-store' if request.headers['Range'].present? && @noid != 'kw52jb973'
        response.headers['Accept-Ranges'] = 'bytes'

        pdf.gsub!(/releases\/\d+/, "current")
        response.headers['X-Sendfile'] = pdf
        send_file pdf
      else
        # This really should *never* happen, but might if the pdf wasn't unpacked right...
        # Consider this an error. We don't want to go through ActiveFedora for this.
        Rails.logger.error("[PDF EBOOK ERROR] The pdf_ebook #{pdf} is not in the derivative directory!!!!")
        response.headers['Content-Length'] ||= @presenter.file.size.to_s
        # Prevent Rack::ETag from calculating a digest over body with a Last-Modified response header
        # any Solr document save will change this, see definition of browser_cache_breaker
        response.headers['Cache-Control'] = 'max-age=31536000, private'
        response.headers['Last-Modified'] = Time.new(@presenter.browser_cache_breaker).utc.strftime("%a, %d %b %Y %T GMT")
        send_data @presenter.file.content, filename: @presenter.label, type: "application/pdf", disposition: "inline"
      end
    end
  rescue StandardError => e
    Rails.logger.info("EPubsController.file raised #{e}")
    head :no_content
  end

  def search
    return head :not_found unless @policy.show?

    if Rails.env.development?
      headers['Access-Control-Allow-Origin'] = '*'
      headers['Access-Control-Allow-Methods'] = 'GET'
      headers['Access-Control-Request-Method'] = '*'
    end

    query = params[:q] || ''
    # due to performance issues, must have 3 or more characters to search
    return render json: { q: query, search_results: [] } if query.length < 3

    log = EpubSearchLog.create(noid: @noid, query: query, user: current_actor.email, press: @presenter.parent.subdomain, session_id: session.id)
    start = (Time.now.to_f * 1000.0).to_i

    epub = EPub::Publication.from_directory(UnpackService.root_path_from_noid(@noid, 'epub'))

    # no query caching for platform_admins so they can better test performance issues, HELIO-4082
    results = if current_actor.platform_admin?
                epub.search(query)
              else
                Rails.cache.fetch(search_cache_key(@noid, query), expires_in: 30.days) { epub.search(query) }
              end

    finish = (Time.now.to_f * 1000.0).to_i
    log.update(time: finish - start, hits: results[:search_results].count, search_results: results)

    render json: results
  rescue StandardError => e
    Rails.logger.error "EPubsController.search raised #{e}"
    head :not_found
  end

  def download_interval # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return head :no_content unless EbookIntervalDownloadOperation.new(current_actor, @entity).allowed?
    return head :no_content if params[:title].blank? || params[:chapter_index].blank?
    return head :no_content unless @entity.is_a?(Sighrax::EpubEbook) || @entity.is_a?(Sighrax::PdfEbook)

    chapter_title = params[:title]
    chapter_index = params[:chapter_index]
    chapter_file_name = chapter_index + '.pdf'
    chapter_download_name = chapter_index + '_' + chapter_title.gsub(/[^0-9A-Za-z\-]/, ' ').squish.tr(' ', '_') + '.pdf'
    chapter_dir = @entity.is_a?(Sighrax::EpubEbook) ? 'epub_chapters' : 'pdf_ebook_chapters'
    chapter_dir_path = UnpackService.root_path_from_noid(@noid, chapter_dir)

    chapter_file_path = File.join(chapter_dir_path, chapter_file_name)
    run_watermark_checks(chapter_file_path)

    CounterService.from(self, @presenter).count(request: 1, section_type: "Chapter", section: chapter_title)
    send_irus_analytics_request
    send_data watermark_pdf(@entity, chapter_title, chapter_file_path, chapter_index), type: "application/pdf", filename: chapter_download_name, disposition: "inline"
  rescue StandardError => e
    Rails.logger.error "EPubsController.download_interval raised #{e}"
    head :no_content
  end

  def share_link
    return head :no_content unless @policy.show?

    subdomain = @parent_presenter.subdomain
    if Press.where(subdomain: subdomain).first&.allow_share_links?
      expire = Time.now.to_i + 28 * 24 * 3600 # 28 days in seconds
      token = JsonWebToken.encode(data: @parent_presenter.id, exp: expire)
      ShareLinkLog.create(ip_address: request.ip,
                          institution: current_institutions.map(&:name).join("|"),
                          press: subdomain,
                          user: current_actor.email,
                          title: @parent_presenter.title,
                          noid: @parent_presenter.id,
                          token: token,
                          action: 'create')
      render plain: Rails.application.routes.url_helpers.epub_url(@noid, share: token)
    else
      head :no_content
    end
  rescue StandardError => e
    Rails.logger.error(%Q|EPubsController.share_link raised #{e} #{e.backtrace.join("\n")}|)
    head :no_content
  end

  private

    def setup
      @noid = params[:id]
      raise(PageNotFoundError, "Invalid NOID") unless ValidationService.valid_noid?(@noid)
      @presenter = Hyrax::PresenterFactory.build_for(ids: [@noid], presenter_class: Hyrax::FileSetPresenter, presenter_args: nil).first
      @entity = Sighrax.from_presenter(@presenter)
      @parent_presenter = @presenter.parent
      raise(NotAuthorizedError, "Non Electronic Publication") unless @entity.is_a?(Sighrax::EpubEbook) || @entity.is_a?(Sighrax::PdfEbook)
      @share_link = params[:share] || session[:share_link]
      session[:share_link] = @share_link
      @policy = EPubPolicy.new(current_actor, @entity, valid_share_link?)
      # determine whether CSB should show an assets tab for this user (`rows: 1` because we don't need the actual results)
      assets_finding_clause = "+monograph_id_ssim:#{@parent_presenter.id} AND -hidden_representative_bsi:true AND -tombstone_ssim:yes"
      @monograph_assets_present = ActiveFedora::SolrService.query("#{assets_finding_clause} #{assets_visibility_clause}",
                                                                  fl: [:id],
                                                                  rows: 1).present?
    end

    # A user who can load the stats dashboard has a role of "analyst" or above, and so should be able to see draft...
    # assets if they click CSB's "assets" button. Authors using a share link to view a draft book should also be...
    # able to do this, but anonymous users should not.
    def assets_visibility_clause
      if valid_share_link? || current_ability.can?(:read, :stats_dashboard)
        nil
      else
        'AND -visibility_ssi:restricted'
      end
    end

    def log_share_link_use
      return unless valid_share_link?
      ShareLinkLog.create(ip_address: request.ip,
                          institution: current_institutions.map(&:name).join("|"),
                          press: @subdomain,
                          user: current_actor.email,
                          title: @parent_presenter.title,
                          noid: @parent_presenter.id,
                          token: @share_link,
                          action: 'use')
    end

    def valid_share_link?
      if @share_link.present?
        begin
          decoded = JsonWebToken.decode(@share_link)
          return true if decoded[:data] == @parent_presenter.id
        rescue JWT::ExpiredSignature, JWT::VerificationError
          return false
        end
      end
      false
    end

    def component_institutions
      institutions = []
      component_products.each { |product| institutions += product.institutions }
      institutions.uniq
    end

    def component_products
      return [] if component.blank?
      products = component.products
      return [] if products.blank?
      products
    end

    def component
      @component ||= Greensub::Component.find_by(noid: @parent_noid)
    end

    def search_cache_key(id, query)
      "epub:" +
        Digest::MD5.hexdigest(query) +
        id +
        @presenter.date_modified.to_s
    end

    def pdf_cache_key(id, chapter_title, chapter_index = nil)
      chapter_index = chapter_index.to_s + "-" if chapter_index.present?
      "pdf:" + chapter_index.to_s + Digest::MD5.hexdigest(chapter_title) + id + @presenter.date_modified.to_s
    end

    # pdf_ebooks reps' chapters can be re-unpacked without ever touching Solr/Fedora
    def cache_key_timestamp
      File.mtime(UnpackService.root_path_from_noid(@entity.noid, 'pdf_ebook_chapters')).to_i
    rescue StandardError => _e
      ''
    end
end
