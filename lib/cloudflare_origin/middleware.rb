require "active_support"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/object/blank"
require "active_support/security_utils"
require "digest"
require "resolv"

module CloudflareOrigin
  # Raised for a request that carries the origin secret but no usable CF-Connecting-IP. Cloudflare
  # always sends that header, so its absence means a zone setting or Worker changed it; failing loudly
  # beats recording the proxy's address as every visitor's without anyone noticing.
  class InvalidClientIpError < StandardError; end

  # Answers only requests that came through Cloudflare, and takes the client IP from
  # CF-Connecting-IP on those. A Request Header Transform Rule on the zone sets X-Origin-Secret to a
  # secret the app also holds, so a request that reached the origin directly lacks it and gets a 403.
  #
  # Two secrets are accepted so the value can rotate without an outage: set the new one as the
  # current secret and the old one as the previous secret, deploy, switch the Cloudflare rule to the
  # new value, then drop the previous one.
  #
  # A GET or HEAD of /up stays open to the platform's health check, which reaches the app directly
  # and cannot carry the header. A /up that came through Cloudflare (it carries CF-Ray) still needs
  # the secret, so a smoke check against the public hostname fails when the rule is missing or wrong.
  class Middleware
    SECRET_HEADER = "HTTP_X_ORIGIN_SECRET".freeze

    # With these gone and REMOTE_ADDR set to the visitor, Rack's request.ip and Rails' remote_ip
    # both return REMOTE_ADDR, and Rails' spoofing check has nothing to compare, so a forged header
    # can neither choose the client IP nor raise IpSpoofAttackError. X-Real-IP goes too, because some error trackers take the client IP from it.
    # X-Forwarded-Proto and X-Forwarded-Port stay, since Cloudflare and the proxy server in front of
    # the app set them.
    FORWARDING_HEADERS = %w[
      HTTP_CLIENT_IP
      HTTP_FORWARDED
      HTTP_X_FORWARDED_FOR
      HTTP_X_FORWARDED_HOST
      HTTP_X_REAL_IP
    ].freeze

    CLIENT_IP_HEADER = "HTTP_CF_CONNECTING_IP".freeze

    HEALTH_CHECK_METHODS = %w[GET HEAD].freeze

    # `openssl rand -hex 32` makes 64 characters, so anything shorter than half of that is a
    # placeholder or a paste gone wrong, and guessable.
    MINIMUM_LENGTH = 32

    def initialize(app, current:, previous:)
      @app = app
      current, previous = current.to_s, previous.to_s
      # A blank value would 403 every page. Failing at boot stops the release, so no machine is
      # replaced.
      raise ArgumentError, "the current Cloudflare origin secret is blank" if current.blank?

      secrets = [current, previous].compact_blank
      if secrets.any? { it.length < MINIMUM_LENGTH }
        raise ArgumentError, "a Cloudflare origin secret is shorter than #{MINIMUM_LENGTH} characters"
      end

      @digests = secrets.map { digest it }
    end

    def call(env)
      # Removed before the /up decision, so the unguarded health check path is covered too.
      FORWARDING_HEADERS.each { env.delete it }
      # Removed before anything downstream runs, so the value never reaches logs or error reports.
      header = env.delete SECRET_HEADER
      return @app.call env if rails_health_check? env
      return forbidden unless header

      given = digest header
      return forbidden unless @digests.any? { ActiveSupport::SecurityUtils.fixed_length_secure_compare it, given }

      env["REMOTE_ADDR"] = client_ip env
      @app.call env
    end

    private

    def rails_health_check?(env)
      env["PATH_INFO"] == "/up" && HEALTH_CHECK_METHODS.include?(env["REQUEST_METHOD"]) && !env.key?("HTTP_CF_RAY")
    end

    def client_ip(env)
      value = env[CLIENT_IP_HEADER]
      raise InvalidClientIpError, "CF-Connecting-IP is missing" if value.blank?
      raise InvalidClientIpError, "CF-Connecting-IP is not an IP address" unless ip_address? value

      value
    rescue InvalidClientIpError => error
      # This middleware sits above ActionDispatch::Executor, so Rails' own error reporting never sees
      # the raise; only an app-server hook would. Reporting here reaches every Rails.error subscriber.
      ActiveSupport.error_reporter.report error, handled: false, source: "rails-cloudflare-origin"
      raise
    end

    # The Resolv patterns match a bare address only, where IPAddr.new would also take a CIDR range.
    def ip_address?(value)
      value.match?(Resolv::IPv4::Regex) || value.match?(Resolv::IPv6::Regex)
    end

    # A fresh response each time, so a caller that adds headers to one cannot change the next. Never
    # cached, so a 403 served while the rule's value is wrong does not outlive the fix at
    # Cloudflare's edge.
    def forbidden
      [403, {"content-type" => "text/plain", "cache-control" => "no-store"}, ["Forbidden"]]
    end

    # Compared as fixed-length digests, so values of different lengths neither raise nor return early.
    def digest(value)
      Digest::SHA256.digest value
    end
  end
end
