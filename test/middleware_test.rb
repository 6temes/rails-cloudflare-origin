require "test_helper"
require "action_dispatch"
require "json"
require "rack/mock_request"

class MiddlewareTest < ActiveSupport::TestCase
  CURRENT = "current-secret-0123456789abcdef0123456789"
  PREVIOUS = "previous-secret-0123456789abcdef012345678"
  PROXY_ADDRESS = "172.16.0.2"
  # Literal rather than read from the middleware, so dropping a header from its list fails a test.
  STRIPPED_HEADERS = %w[HTTP_CLIENT_IP HTTP_FORWARDED HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_HOST HTTP_X_REAL_IP HTTP_X_ORIGIN_SECRET].freeze
  FORGED = {
    "HTTP_FORWARDED" => "for=10.0.0.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.4", "HTTP_CLIENT_IP" => "10.0.0.2",
    "HTTP_X_REAL_IP" => "10.0.0.3", "HTTP_X_FORWARDED_HOST" => "evil.example.net"
  }.freeze

  # Reports what a Rails app would see, through the real RemoteIp middleware, so a forged header
  # that would make Rails raise or pick the wrong client shows up here.
  def downstream
    app = lambda do |env|
      request = ActionDispatch::Request.new env
      seen = {
        "ip" => request.ip,
        "remote_ip" => request.remote_ip,
        "present" => STRIPPED_HEADERS.select { env.key? it },
        "x_forwarded_proto" => env["HTTP_X_FORWARDED_PROTO"]
      }
      [200, {"content-type" => "application/json"}, [seen.to_json]]
    end
    ActionDispatch::RemoteIp.new app
  end

  def middleware(current: CURRENT, previous: PREVIOUS)
    CloudflareOrigin::Middleware.new downstream, current:, previous:
  end

  # Rack::MockRequest.env_for sets no HTTP_* header, so every test states each header it relies on,
  # and REMOTE_ADDR is the proxy's address as it would be at the origin.
  def call(path = "/", method: "GET", headers: {}, **secrets)
    env = Rack::MockRequest.env_for path, :method => method, "REMOTE_ADDR" => PROXY_ADDRESS, "HTTP_HOST" => "app.example.com"
    env.merge! headers
    middleware(**secrets).call env
  end

  def through_cloudflare(secret: CURRENT, client_ip: "203.0.113.7", **headers)
    {"HTTP_X_ORIGIN_SECRET" => secret, "HTTP_CF_CONNECTING_IP" => client_ip, "HTTP_CF_RAY" => "8f1c2d3e4f5a6b7c-NRT"}
      .merge(headers).compact
  end

  def seen(response)
    status, _headers, body = response
    assert_equal 200, status
    JSON.parse body.join
  end

  def assert_client(ip, result)
    assert_equal ip, result["ip"]
    assert_equal ip, result["remote_ip"]
  end

  test "takes the client IP from CF-Connecting-IP on a request carrying the current secret" do
    assert_client "203.0.113.7", seen(call(headers: through_cloudflare))
  end

  test "accepts the previous secret the same way" do
    assert_client "203.0.113.7", seen(call(headers: through_cloudflare(secret: PREVIOUS)))
  end

  test "passes an IPv6 client through unchanged" do
    assert_client "2001:db8::7", seen(call(headers: through_cloudflare(client_ip: "2001:db8::7")))
  end

  test "refuses a wrong secret with an uncached 403" do
    status, headers, body = call headers: through_cloudflare(secret: "wrong-secret-0123456789abcdef0123456789")

    assert_equal 403, status
    assert_equal "no-store", headers["cache-control"]
    assert_equal ["Forbidden"], body
  end

  test "refuses a request without the secret header" do
    status, headers, _body = call headers: through_cloudflare(secret: nil)

    assert_equal 403, status
    assert_equal "no-store", headers["cache-control"]
  end

  test "refuses a secret that only differs in length" do
    assert_equal 403, call(headers: through_cloudflare(secret: "#{CURRENT}-and-more")).first
    assert_equal 403, call(headers: through_cloudflare(secret: CURRENT.chop)).first
  end

  test "raises when a verified request has no CF-Connecting-IP" do
    error = assert_raises(CloudflareOrigin::InvalidClientIpError) { call headers: through_cloudflare(client_ip: nil) }
    assert_equal "CF-Connecting-IP is missing", error.message
  end

  ["not-an-ip", "203.0.113.0/24", "203.0.113.7, 198.51.100.4"].each do |value|
    test "raises when CF-Connecting-IP is #{value.inspect}" do
      error = assert_raises(CloudflareOrigin::InvalidClientIpError) { call headers: through_cloudflare(client_ip: value) }
      assert_equal "CF-Connecting-IP is not an IP address", error.message
    end
  end

  test "reports an invalid CF-Connecting-IP to Rails.error before raising" do
    reports = []
    subscriber = Object.new
    subscriber.define_singleton_method(:report) { |error, **options| reports << [error, options] }
    ActiveSupport.error_reporter.subscribe subscriber

    assert_raises(CloudflareOrigin::InvalidClientIpError) { call headers: through_cloudflare(client_ip: "not-an-ip") }
    assert_equal 1, reports.size
    error, options = reports.first
    assert_instance_of CloudflareOrigin::InvalidClientIpError, error
    assert_equal false, options[:handled]
    assert_equal "rails-cloudflare-origin", options[:source]
  ensure
    ActiveSupport.error_reporter.unsubscribe subscriber
  end

  test "ignores conflicting Forwarded and X-Forwarded-For headers instead of raising" do
    headers = through_cloudflare "HTTP_FORWARDED" => "for=10.0.0.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.4"

    assert_client "203.0.113.7", seen(call(headers:))
  end

  test "ignores a forged Client-IP header" do
    assert_client "203.0.113.7", seen(call(headers: through_cloudflare("HTTP_CLIENT_IP" => "10.0.0.1")))
  end

  test "removes the forwarding headers and the secret before the app runs" do
    assert_empty seen(call(headers: through_cloudflare(**FORGED)))["present"]
  end

  test "keeps X-Forwarded-Proto" do
    result = seen call(headers: through_cloudflare("HTTP_X_FORWARDED_PROTO" => "https"))

    assert_equal "https", result["x_forwarded_proto"]
  end

  test "health check: passes GET and HEAD of /up without the secret" do
    assert_equal 200, call("/up").first
    assert_equal 200, call("/up", method: "HEAD").first
  end

  test "health check: still removes every forwarding header, without raising" do
    result = seen call("/up", headers: FORGED)

    assert_empty result["present"]
    assert_equal PROXY_ADDRESS, result["remote_ip"]
  end

  test "health check: keeps the secret header from reaching the app" do
    assert_empty seen(call("/up", headers: {"HTTP_X_ORIGIN_SECRET" => CURRENT}))["present"]
  end

  test "health check: refuses POST /up without the secret" do
    assert_equal 403, call("/up", method: "POST").first
  end

  test "health check: refuses a /up that came through Cloudflare without the secret" do
    assert_equal 403, call("/up", headers: {"HTTP_CF_RAY" => "8f1c2d3e4f5a6b7c-NRT"}).first
  end

  ["/up/extra", "/upload", "/up/", "/up.json"].each do |path|
    test "health check: refuses #{path}, which only starts with /up" do
      assert_equal 403, call(path).first
    end
  end

  test "does not let an empty header through when the previous secret is empty" do
    assert_equal 403, call(headers: through_cloudflare(secret: ""), previous: "").first
  end

  # Credentials come from YAML, where an all-digit value is read as an Integer.
  test "compares the string form of a secret YAML read as a number" do
    number = 12_345_678_901_234_567_890_123_456_789_012_345

    assert_equal 200, call(headers: through_cloudflare(secret: number.to_s), current: number).first
  end

  [nil, "", "   "].each do |blank|
    test "refuses to start with a current secret of #{blank.inspect}, previous secret or not" do
      [nil, PREVIOUS].each do |previous|
        error = assert_raises(ArgumentError) { middleware current: blank, previous: }
        assert_equal "the current Cloudflare origin secret is blank", error.message
      end
    end
  end

  test "refuses to start with a secret shorter than 32 characters" do
    long = "a" * 32

    assert_raises(ArgumentError) { middleware current: "a" * 31, previous: nil }
    assert_raises(ArgumentError) { middleware current: long, previous: "a" * 31 }
    assert_nothing_raised { middleware current: long, previous: long }
  end
end
