# frozen_string_literal: true

Hyrax::FileSetsController.class_eval do # rubocop:disable Metrics/BlockLength
  prepend(FileSetsControllerBehavior = Module.new do
    Hyrax::FileSetsController.form_class = ::Heliotrope::FileSetEditForm
    include IrusAnalytics::Controller::AnalyticsBehaviour
    include Skylight::Helpers

    instrument_method
    def show # rubocop:disable Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      # local heliotrope changes
      # HELIO-4673, use a pass-through URL param on a standard show-page DOI for direct download
      return redirect_to(Hyrax::Engine.routes.url_helpers.download_path(params[:id])) if params[:download] == 'true'
      # Prevent users seeing show pages of representative FileSets byt redirecting to the parent Monograph
      (redirect_to Rails.application.routes.url_helpers.monograph_catalog_path(presenter&.parent&.id)) && return if bounce_from_representatives?

      # Presently resources are not restricted but if someone is following a WAYFless URL
      # then redirect them to shib login.
      wayfless_redirect_to_shib_login

      if presenter.multimedia?
        CounterService.from(self, presenter).count(request: 1)
        send_irus_analytics_request
      else
        CounterService.from(self, presenter).count
        send_irus_analytics_investigation
      end

      # See HELIO-1606 regarding the `admin_override` stuff (`false` param). Basically don't show a download button...
      # to editors/admins unless the public would also see one, i.e. the metadata is set correctly.
      @resource_download_operation_allowed ||= ResourceDownloadOperation.new(current_actor, Sighrax.from_noid(params[:id])).allowed?(false)

      auth_for(Sighrax.from_presenter(@presenter))

      respond_to do |wants|
        wants.html { presenter }
        wants.json { presenter }
        additional_response_formats(wants)
      end
    end

    # HELIO-4143
    def item_identifier_for_irus_analytics
      CatalogController.blacklight_config.oai[:provider][:record_prefix] + ":" + presenter&.parent&.id
    end

    def edit
      # @resource_download_operation_allowed needed in edit() as well as show() because of the "mini show view" included on the edit form.
      # At least that is my assumption. With the Module prepend override stuff it's too egregious to create an...
      # initialize/setup method on the overriden class. So just duplicate. We should probably remove that partial at some point.
      @resource_download_operation_allowed ||= ResourceDownloadOperation.new(current_actor, Sighrax.from_noid(params[:id])).allowed?(false)
      initialize_edit_form
    end

    def destroy
      FeaturedRepresentative.where(file_set_id: params[:id]).first&.destroy
      EbookTableOfContentsCache.find_by(noid: params[:id])&.destroy
      super
    end

    def bounce_from_representatives?
      # non-editors and search engines shouldn't see show pages for covers or "representative" FileSets, with the...
      # exception of the "Gabii-specific" FeaturedRepresentatives, which have a `kind` of 'database' or 'webgl'
      featured_rep = FeaturedRepresentative.where(file_set_id: params[:id]).first
      return false unless featured_rep.present? || [presenter&.parent&.representative_id, presenter&.parent&.thumbnail_id].include?(params[:id])
      return false if ['database', 'webgl'].include?(featured_rep&.kind)
      !(can? :edit, params[:id])
    end

    # this is provided so that implementing application can override this behavior and map params to different attributes
    def update_metadata
      file_attributes = form_class.model_attributes(attributes)
      if /^interactive map$/i.match?(file_attributes['resource_type']&.first)
        UnpackJob.perform_later(params[:id], 'interactive_map') unless Sighrax.from_noid(params[:id]).is_a?(Sighrax::InteractiveMap)
      end
      actor.update_metadata(file_attributes)
    end

    def attempt_update
      if wants_to_revert?
        actor.revert_content(params[:revision])
      elsif params.key?(:user_thumbnail)
        change_thumbnail  # heliotrope override
      elsif params.key?(:file_set)
        if params[:file_set].key?(:files)
          actor.update_content(uploaded_file_from_path)
        else
          update_metadata
        end
      elsif params.key?(:files_files) # version file already uploaded with ref id in :files_files array
        uploaded_files = Array(Hyrax::UploadedFile.find(params[:files_files]))
        actor.update_content(uploaded_files.first)
        update_metadata
      end
    end

    def uploaded_file_from_path
      uploaded_file = CarrierWave::SanitizedFile.new(params[:file_set][:files].first)
      Hyrax::UploadedFile.create(user_id: current_user.id, file: uploaded_file)
    end

    def change_thumbnail
      dest = Hyrax::DerivativePath.derivative_path_for_reference(params[:id], 'thumbnail')

      if params[:user_thumbnail].key?(:custom_thumbnail)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(params[:user_thumbnail][:custom_thumbnail].path, dest)
        # Because the file at `params[:user_thumbnail][:custom_thumbnail].path` was created with Tempfile.new (see...
        # Rack::Multipart::UploadedFile.initialize), it has 0600 permissions, so we need to chmod for X-Sendfile to work.
        File.chmod(0664, dest)
      end
      if params[:user_thumbnail].key?(:use_default)
        if params[:user_thumbnail][:use_default] == '1'
          FileUtils.rm(dest) if File.exist?(dest)
          ActiveFedora::SolrService.add(@file_set.to_solr.merge(thumbnail_path_ss: ActionController::Base.helpers.image_path('default.png')), softCommit: true)
        else
          ActiveFedora::SolrService.add(@file_set.to_solr.merge(thumbnail_path_ss: Hyrax::Engine.routes.url_helpers.download_path(@file_set.id, file: 'thumbnail')), softCommit: true)
        end
      end
      # neither FileUtils nor SolrService return useful values, so both a FileUtils.compare_file and Solr query would...
      # be necessary to check for overall success. Not going to bother with that for now, returning `true`.
      true
    end

    def reindex
      UpdateIndexJob.perform_later(params[:id])
      redirect_to [main_app, @file_set], notice: "Reindexing Job Scheduled"
    end

    # Heliotrope Override
    # Heliotrope doesn't use Workflow at all, but the WorkflowsHelper is included in Hyrax 3's FileSetController
    # which can raise a WorkflowAuthorizationException under certain conditions. For instance:
    #
    # raise WorkflowAuthorizationException if presenter.parent.blank?
    #
    # really messes up our orpan FileSet redirects.
    #
    # Heliotrope Override: Heliotrope doesn't care about this, just pass through
    # See hyrax, https://github.com/samvera/hyrax/commit/cb21570fadcea0b8d1dfd0b7cffecf5135c1ea76
    # See hyrax, https://github.com/samvera/hyrax/commit/1efe93929285985751cc270675c243f628cf31ca
    def presenter
      @presenter ||= if valid_share_link?
                       @share_link_presenter
                     else
                       show_presenter.new(curation_concern_document, current_ability, request)
                     end
    end

    def valid_share_link?
      return @valid_share_link if @valid_share_link.present?

      share_link = params[:share] || session[:share_link]
      session[:share_link] = share_link

      @valid_share_link = if share_link.present?
                            @share_link_presenter = show_presenter.new(::SolrDocument.find(params[:id]), current_ability, request)

                            begin
                              decoded = JsonWebToken.decode(share_link)
                              true if decoded[:data] == @share_link_presenter&.parent&.id
                            rescue JWT::ExpiredSignature
                              false
                            end
                          end
    end

    def default_url_options
      @valid_share_link = true if valid_share_link?
      super
    end
  end)
end
