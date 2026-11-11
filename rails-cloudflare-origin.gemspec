require_relative "lib/cloudflare_origin/version"

Gem::Specification.new do |spec|
  spec.name = "rails-cloudflare-origin"
  spec.version = CloudflareOrigin::VERSION
  spec.authors = ["Kokorono"]
  spec.summary = "Refuse requests that bypass Cloudflare and take the client IP from CF-Connecting-IP"
  spec.description = "A Rack middleware, installed by a Railtie at the top of the stack, that requires a " \
                     "Cloudflare-added origin secret, strips client IP headers a visitor can forge, and " \
                     "sets the client IP from CF-Connecting-IP."
  spec.homepage = "https://github.com/6temes/rails-cloudflare-origin"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/releases",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage
  }

  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "railties", ">= 8.1"
end
