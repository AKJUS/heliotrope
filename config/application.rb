# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'
require 'semantic_logger'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Heliotrope
  class Application < Rails::Application
    # a definitive place for our "tempish" files, many of which do persist for a short time and/or are shared between...
    # separate components of the stack (jobs etc)
    raise 'You must set `Settings.scratch_space_path`' unless Settings.scratch_space_path
    raise "`Settings.scratch_space_path` directory (`#{Settings.scratch_space_path}`) must exist" unless Dir.exist?(Settings.scratch_space_path)

    # RIIIF will create `Settings.riiif_network_files_path` if it doesn't exist:
    # https://github.com/sul-dlss/riiif/blob/a78b329d9871cee6a01b3851fd564f9c62e43572/app/resolvers/riiif/http_file_resolver.rb#L86
    raise 'You must set `Settings.riiif_network_files_path`' unless Settings.riiif_network_files_path

    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.1

    config.generators do |g|
      g.test_framework :rspec, spec: true
    end

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de

    config.active_job.queue_adapter = :resque

    # Add concerns to autoload paths
    config.autoload_paths += %W[#{config.root}/app/presenters/concerns]

    # Add lib directory to autoload paths
    config.autoload_paths << "#{config.root}/lib"
    config.autoload_paths << "#{config.root}/lib/devise"

    # For properly generating URLs and minting DOIs - the app may not by default
    # Outside of a request context the hostname needs to be provided.
    config.hostname = Settings.host

    # Set default host
    Rails.application.routes.default_url_options[:host] = config.hostname

    # HELIO-4632 Deprecation warnings in production fill up systemd logs pointlessly
    if Rails.env.production?
      # We try to silence most deprecations with this. However, I suspect that gems are actually
      # loaded before this so I'm unsure how well it's going to work. Might be more effective in
      # config/environment.rg or something. But, really the problem we're running into is blacklight.
      ActiveSupport::Deprecation.behavior = :silence
      # Blacklight specific which is like 99% of "read" deprecation warnings
      # Putting this here works to silence in blacklight deprecation warnings
      Deprecation.default_deprecation_behavior = :silence
    end

    # Affirmative login means that we only log someone into the application
    # when they actively initiate a login, even if they have an SSO session
    # that we recognize and could log them in automatically.
    #
    # session[:log_me_in] flag is set true when login initiated by user
    #
    # See the KeycardAuthenticatable strategy for more detail.

    # Auto login means that, if we ever access a protected resource (such that
    # the Devise authenticate_user! filter is called), we will automatically
    # sign the user into the application if they have an SSO session active.
    #
    # See the KeycardAuthenticatable strategy for more detail.
    config.auto_login = Settings.auto_login && true

    # Automatic account creation on login
    # Should we create users automatically on first login?
    # This supports convenient single sign-on account provisioning
    #
    # See the KeycardAuthenticatable strategy for more detail.
    config.create_user_on_login = Settings.create_user_on_login && true

    # HELIO-4700 use Semantic Logger
    # config.semantic_logger.add_appender(io: STDOUT, level: :debug, formatter: :color)
    # config.active_record.logger = SemanticLogger[ActiveRecord::Base]

    # Prepend all log lines with the following tags.
    # Can be overridden in environments/development and environments/test
    config.log_tags = {
      id: :request_id,
      ip: :remote_ip
    }

    if ENV["RAILS_LOG_TO_STDOUT"].present?
      $stdout.sync = true
      config.rails_semantic_logger.add_file_appender = false
      config.semantic_logger.add_appender(
        io: $stdout, formatter: config.rails_semantic_logger.format
      )
    end

    # HELIO-4075 Set java.io.tmpdir to `Settings.scratch_space_path`
    # Ensure tmp directories are defined (Cut and pasted from DBD October 14, 2021 then modified for Fulcrum)
    verbose_init = false
    if verbose_init
      Rails.logger.info "ENV TMPDIR -- BEFORE -- Application Configuration"
      Rails.logger.info "ENV['TMPDIR']=#{ENV['TMPDIR']}"
      Rails.logger.info "ENV['_JAVA_OPTIONS']=#{ENV['_JAVA_OPTIONS']}"
      Rails.logger.info "ENV['JAVA_OPTIONS']=#{ENV['JAVA_OPTIONS']}"
    end

    # 20230515: When it comes to scratch_space_path,  we definitely don't want to use system `/tmp`, which has always...
    # had very limited space. Neither do we want to use app temp `Rails.root.join('tmp')`, which is similarly...
    # restricted on the new production servers.
    # Additionally, the files the stack writes to "temporary" storage are more like scratch space files, so we'll..
    # use a dedicated mount for these. See HELIO-627, http://stackoverflow.com/a/17068331, HELIO-4471.
    # note: we have used app tmp for this for many years on the old servers, so that will be the fall-back
    tmpdir = Settings.scratch_space_path

    ENV['TMPDIR'] = tmpdir
    ENV['_JAVA_OPTIONS'] = "-Djava.io.tmpdir=#{tmpdir}" if ENV['_JAVA_OPTIONS'].blank?
    ENV['JAVA_OPTIONS'] = "-Djava.io.tmpdir=#{tmpdir}" if ENV['JAVA_OPTIONS'].blank?

    if verbose_init
      Rails.logger.info "ENV TMPDIR -- AFTER -- Application Configuration"
      Rails.logger.info "ENV['TMPDIR']=#{ENV['TMPDIR']}"
      Rails.logger.info "ENV['_JAVA_OPTIONS']=#{ENV['_JAVA_OPTIONS']}"
      Rails.logger.info "ENV['JAVA_OPTIONS']=#{ENV['JAVA_OPTIONS']}"
      Rails.logger.info `echo $TMPDIR`.to_s
      Rails.logger.info `echo $_JAVA_OPTIONS`.to_s
      Rails.logger.info `echo $JAVA_OPTIONS`.to_s
    end

    # Set the epub engine for cozy-sun-bear
    config.cozy_epub_engine = 'epubjs'

    # Prior to Hyrax 4 we removed the middleware probe. In Hyrax 4 this no longer works, but will leave here for now commented out.
    # See HELIO-4589, HELIO-5482 and https://github.com/mlibrary/umrdr/commit/4aa4e63349d6f3aa51d76f07aa20faeae6712719
    # config.skylight.probes -= ['middleware']
    #
    # If you need to test Sklight in development, uncomment this
    # config.skylight.environments << "development" if Rails.env.development?

    # Prometheus monitoring, see HELIO-3388
    ENV["PROMETHEUS_MONITORING_DIR"] = ENV["PROMETHEUS_MONITORING_DIR"] || Settings.prometheus_monitoring.dir || File.join(Settings.scratch_space_path, 'prometheus')
    FileUtils.mkdir_p ENV.fetch("PROMETHEUS_MONITORING_DIR")
    Prometheus::Client.config.data_store = Prometheus::Client::DataStores::DirectFileStore.new(dir: ENV.fetch("PROMETHEUS_MONITORING_DIR"))

    # HELIO-4309
    config.active_record.yaml_column_permitted_classes = [ActiveSupport::HashWithIndifferentAccess]

    # Adding this since config.working_path = Settings.uploads_path
    # in initializers/hyrax.rb doesn't always seem to work
    # HELIO-4186 Most deploys don't use this and inherit the hyrax default of ~/tmp/uploads
    # but the newer deploys and their paired "old" deploy need it
    # https://github.com/samvera/hyrax/blob/4c1a99a6a52c973781dff090c2c98c044ea65e42/lib/hyrax/configuration.rb#L321
    ENV['HYRAX_UPLOAD_PATH'] = Settings.uploads_path

    # Allow `rails webpacker:compile` to run on node versions >= 17 (see HELIO-4624 and https://nodejs.org/en/blog/release/v17.0.0#openssl-30)
    # note: webpacker:compile basically just runs `bin/webpack`. To see the `error:0308010C:digital envelope routines::unsupported`...
    # messages we're avoiding with this you can run the following on a production instance:
    # `NODE_ENV=production ./bin/webpack --progress --config config/webpack/production.js`
    node_major_version = `node -v || nodejs -v`.to_s.scan(/\d/)[0, 2].join.to_i
    # not sure why this doesn't work on CircleCI, TBH. Is it not actually using the version of Node we think it is?
    ENV['NODE_OPTIONS'] = '--openssl-legacy-provider' unless node_major_version < 17 || ENV['CIRCLECI']

    config.to_prepare do
      # ensure overrides are loaded
      # see https://bibwild.wordpress.com/2016/12/27/a-class_eval-monkey-patching-pattern-with-prepend/
      Dir.glob(Rails.root.join('app', '**', '*_override*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end

      # Here we swap out some of the default actor stack, from Hyrax, located
      # (in Hyrax itself) at app/services/default_middleware_stack.rb
      #
      # FIRST IN LINE
      #
      # Insert actor after obtaining lock so we are first in line!
      Hyrax::CurationConcern.actor_factory.insert_after(Hyrax::Actors::OptimisticLockValidator, HeliotropeActor)
      # Maybe register DOIs on update
      Hyrax::CurationConcern.actor_factory.insert_after(HeliotropeActor, RegisterFileSetDoisActor)
      # Heliotrope "importer" style CreateWithFilesActor
      Hyrax::CurationConcern.actor_factory.insert_after(RegisterFileSetDoisActor, CreateWithImportFilesActor)
      #
      # LAST IN LINE
      #
      # Destroy FeaturedRepresentatives on delete
      Hyrax::CurationConcern.actor_factory.insert_after(Hyrax::Actors::CleanupTrophiesActor, FeaturedRepresentativeActor)
    end
  end
end
