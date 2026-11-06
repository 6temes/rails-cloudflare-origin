require "rails/railtie"

module CloudflareOrigin
  class Railtie < Rails::Railtie
    initializer "cloudflare_origin.middleware", after: :load_config_initializers do |app|
      next if Rails.env.local?

      current = Railtie.secret app, :cloudflare_origin_secret
      if current.blank?
        Rails.logger.warn "rails-cloudflare-origin: middleware not installed because no origin secret is configured"
        next
      end

      app.config.middleware.insert_before 0, Middleware,
        current:,
        previous: Railtie.secret(app, :cloudflare_origin_secret_previous)
    end

    # The environment variable wins when set, so a host can supply the secret without editing
    # credentials. A stale variable left on the host therefore overrides a rotated credential.
    def self.secret(app, name)
      ENV[name.to_s.upcase].presence || app.credentials[name]
    end
  end
end
