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

  test "the unreleased placeholder satisfies the >= 0 requirement Bundler gives a git source" do
    assert_operator Gem::Version.new(CloudflareOrigin::VERSION), :>=, Gem::Version.new("0")
  end

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

  test "refuses a placeholder followed by a second VERSION assignment, leaving the file unchanged" do
    placeholder = File.read(@target).chomp.delete_suffix("end")
    [
      %(#{placeholder}=begin\n  VERSION = "9.9.9"\n=end\nend\n),
      %(#{placeholder}  VERSION = "9.9.9" # release version\nend\n),
      %(#{placeholder}  VERSION = VERSION + ".1"\nend\n)
    ].each do |source|
      File.binwrite @target, source

      _, status = stamp "1.2.3"

      assert_not status.success?, "stamped #{source.inspect}"
      assert_equal source, File.binread(@target)
    end
  end

  private

  def stamp(version)
    _, stderr, status = Open3.capture3(RbConfig.ruby, STAMP, version, @target)
    [stderr, status]
  end

  # In a fresh process without bundler, whose setup would load the real
  # version.rb through the gemspec before the stamped copy.
  def loaded_version
    stdout, status = Open3.capture2({"RUBYOPT" => nil}, RbConfig.ruby, "--disable-gems",
      "-e", "load ARGV[0]; print CloudflareOrigin::VERSION", @target)
    assert status.success?
    stdout
  end
end
