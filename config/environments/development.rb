# frozen_string_literal: true

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Middleware to fake authentication header field that would come from apache.
  # See comments in ./lib/devise/fake_auth_header.rb for more details.
  config.middleware.use FakeAuthHeader

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable/disable caching. By default caching is disabled.
  if File.exist?(File.join(Settings.scratch_space_path, 'caching-dev.txt'))
    config.action_controller.perform_caching = true

    # config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.seconds.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  Rails.application.routes.default_url_options[:protocol] = 'http'

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Debug mode disables concatenation and preprocessing of assets.
  # This option may cause significant delays in view rendering with a large
  # number of complex assets.
  config.assets.debug = true

  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  config.assets.digest = true

  # Adds additional error checking when serving assets at runtime.
  # Checks for improperly declared sprockets dependencies.
  # Raises helpful error messages.
  config.assets.raise_runtime_errors = true

  # Suppress logger output for asset requests.
  config.assets.quiet = true

  # Uncomment for No IP tag for development
  # config.log_tags = {
  #   id: :request_id
  # }

  # Raises error for missing translations
  config.action_view.raise_on_missing_translations = true

  # share console to VM host, which gets rid of all the Rails server warnings
  config.web_console.whitelisted_ips = '10.0.2.2'

  # Use an evented file watcher to asynchronously detect changes in source code,
  # routes, locales, etc. This feature depends on the listen gem.
  config.file_watcher = ActiveSupport::EventedFileUpdateChecker

  # HELIO-4827 Observability metrics for development
  # In prod this is configured in puma.rb
  config.middleware.use(Yabeda::Prometheus::Exporter, path: "/metrics")
end
