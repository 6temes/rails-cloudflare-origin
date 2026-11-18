require "test_helper"
require "fileutils"
require "open3"
require "tmpdir"

class StampVersionTest < ActiveSupport::TestCase
  ROOT = File.expand_path("..", __dir__)
  STAMP = File.join(ROOT, "bin/stamp-version")
  VERSION_FILE = File.join(ROOT, "lib/cloudflare_origin/version.rb")

  setup do
    @dir = Dir.mktmpdir
    @target = File.join(@dir, "version.rb")
    FileUtils.cp VERSION_FILE, @target
  end

  teardown { FileUtils.remove_entry @dir }

  test "stamps the version into a copy of the real version.rb" do
    _, status = stamp "1.2.3"

    assert status.success?
    assert_equal "1.2.3", loaded_version
  end

  test "refuses a version that is not a plain gem version, leaving the file unchanged" do
    original = File.read(@target)

    ["abc", "", "1.2.3-rc1"].each do |version|
      stderr, status = stamp version

      assert_not status.success?, "accepted #{version.inspect}"
      assert_match "is not a plain gem version", stderr
      assert_equal original, File.read(@target)
    end
  end

  test "refuses a file without a VERSION literal, leaving it unchanged" do
    File.write @target, "module CloudflareOrigin\nend\n"

    stderr, status = stamp "1.2.3"

    assert_not status.success?
    assert_match "exactly one VERSION literal", stderr
    assert_equal "module CloudflareOrigin\nend\n", File.read(@target)
  end

  private

  def stamp(version)
    _, stderr, status = Open3.capture3(RbConfig.ruby, STAMP, version, @target)
    [stderr, status]
  end

  # In a subprocess, so this suite's own CloudflareOrigin::VERSION is never redefined.
  def loaded_version
    stdout, status = Open3.capture2(RbConfig.ruby, "-e", "load ARGV[0]; print CloudflareOrigin::VERSION", @target)
    assert status.success?
    stdout
  end
end
