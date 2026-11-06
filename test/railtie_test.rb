require "test_helper"
require "active_support/encrypted_configuration"
require "open3"
require "tmpdir"

# Each test boots the dummy app in its own process, since a Rails application initializes only once
# per process and the tests need different environments and credentials.
class RailtieTest < ActiveSupport::TestCase
  DUMMY = File.expand_path "dummy/config/environment", __dir__
  SECRET = "s" * 32
  PREVIOUS = "p" * 32
  SHORT = "x" * 31
  WARNING = "middleware not installed because no origin secret is configured"

  def boot(rails_env:, credentials: nil, env: {})
    Dir.mktmpdir do |dir|
      # Unset unless a test sets them, so a secret in the developer's shell cannot leak in.
      child_env = {"RAILS_ENV" => rails_env, "SECRET_KEY_BASE" => "k" * 64,
                   "CLOUDFLARE_ORIGIN_SECRET" => nil, "CLOUDFLARE_ORIGIN_SECRET_PREVIOUS" => nil}.merge env

      if credentials
        key_path = File.join dir, "credentials.key"
        File.write key_path, ActiveSupport::EncryptedConfiguration.generate_key
        path = File.join dir, "credentials.yml.enc"
        ActiveSupport::EncryptedConfiguration
          .new(config_path: path, key_path:, env_key: "UNUSED", raise_if_missing_key: true)
          .write(credentials.to_yaml)
        child_env["DUMMY_CREDENTIALS_PATH"] = path
        child_env["RAILS_MASTER_KEY"] = File.read key_path
      end

      script = "require #{DUMMY.dump}; puts Rails.application.middleware.map(&:name)"
      Open3.capture3 child_env, RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script
    end
  end

  def stack(...)
    stdout, stderr, status = boot(...)
    raise "dummy app failed to boot:\n#{stderr}" unless status.success?

    stdout.split "\n"
  end

  def assert_boot_fails(...)
    _stdout, stderr, status = boot(...)
    assert_not status.success?, "expected the boot to fail"
    assert_includes stderr, "shorter than 32 characters"
  end

  def assert_installs(...)
    assert_equal "CloudflareOrigin::Middleware", stack(...).first
  end

  test "installs the middleware above the app's own insert_before 0 and the default stack" do
    names = stack rails_env: "production", credentials: {"cloudflare_origin_secret" => SECRET}

    assert_equal "CloudflareOrigin::Middleware", names.first
    %w[InitializerMiddleware EnvironmentMiddleware ActionDispatch::HostAuthorization ActionDispatch::SSL].each do
      assert_includes names, it
    end
  end

  test "without a current secret: installs nothing and warns in production" do
    _stdout, stderr, status = boot rails_env: "production", credentials: {"unrelated" => "value"}

    assert status.success?, stderr
    assert_includes stderr, WARNING
  end

  test "without a current secret: keeps the middleware out of the stack in production" do
    assert_not_includes stack(rails_env: "production"), "CloudflareOrigin::Middleware"
  end

  test "without a current secret: treats a blank credential as absent" do
    assert_not_includes stack(rails_env: "production", credentials: {"cloudflare_origin_secret" => ""}),
      "CloudflareOrigin::Middleware"
  end

  test "without a current secret: does not warn in the test environment" do
    _stdout, stderr, _status = boot rails_env: "test"

    assert_not_includes stderr, WARNING
  end

  test "installs nothing in the test environment, even with a secret" do
    names = stack rails_env: "test", credentials: {"cloudflare_origin_secret" => SECRET},
      env: {"CLOUDFLARE_ORIGIN_SECRET" => SECRET}

    assert_equal "InitializerMiddleware", names.first
    assert_not_includes names, "CloudflareOrigin::Middleware"
  end

  test "accepts a previous secret alongside the current one" do
    assert_installs rails_env: "production",
      credentials: {"cloudflare_origin_secret" => SECRET, "cloudflare_origin_secret_previous" => PREVIOUS}
  end

  test "treats a blank previous secret as absent" do
    assert_installs rails_env: "production",
      credentials: {"cloudflare_origin_secret" => SECRET, "cloudflare_origin_secret_previous" => ""}
  end

  test "fails the boot when the current credential is shorter than 32 characters" do
    assert_boot_fails rails_env: "production", credentials: {"cloudflare_origin_secret" => SHORT}
  end

  test "fails the boot when the previous credential is shorter than 32 characters" do
    assert_boot_fails rails_env: "production",
      credentials: {"cloudflare_origin_secret" => SECRET, "cloudflare_origin_secret_previous" => SHORT}
  end

  test "environment: installs from the variable alone" do
    assert_installs rails_env: "production", env: {"CLOUDFLARE_ORIGIN_SECRET" => SECRET}
  end

  test "environment: fails the boot when the current variable is shorter than 32 characters" do
    assert_boot_fails rails_env: "production", env: {"CLOUDFLARE_ORIGIN_SECRET" => SHORT}
  end

  test "environment: prefers the current variable over the credential" do
    assert_installs rails_env: "production", credentials: {"cloudflare_origin_secret" => SHORT},
      env: {"CLOUDFLARE_ORIGIN_SECRET" => SECRET}
    assert_boot_fails rails_env: "production", credentials: {"cloudflare_origin_secret" => SECRET},
      env: {"CLOUDFLARE_ORIGIN_SECRET" => SHORT}
  end

  test "environment: prefers the previous variable over the credential" do
    credentials = {"cloudflare_origin_secret" => SECRET}

    assert_installs rails_env: "production", credentials: credentials.merge("cloudflare_origin_secret_previous" => SHORT),
      env: {"CLOUDFLARE_ORIGIN_SECRET_PREVIOUS" => PREVIOUS}
    assert_boot_fails rails_env: "production", credentials: credentials.merge("cloudflare_origin_secret_previous" => PREVIOUS),
      env: {"CLOUDFLARE_ORIGIN_SECRET_PREVIOUS" => SHORT}
  end

  test "environment: falls back to the credentials when the variables are blank" do
    blank = {"CLOUDFLARE_ORIGIN_SECRET" => "", "CLOUDFLARE_ORIGIN_SECRET_PREVIOUS" => ""}

    assert_installs rails_env: "production", credentials: {"cloudflare_origin_secret" => SECRET}, env: blank
    assert_boot_fails rails_env: "production", credentials: {"cloudflare_origin_secret" => SHORT}, env: blank
    assert_boot_fails rails_env: "production",
      credentials: {"cloudflare_origin_secret" => SECRET, "cloudflare_origin_secret_previous" => SHORT},
      env: blank
  end
end
