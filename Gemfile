source "https://rubygems.org"

# Brings in the gem's runtime dependencies (actionpack and railties).
gemspec

# Development only, so the release workflow's publish job can install without them.
group :development do
  # Runs the middleware and Railtie tests.
  gem "minitest", require: false
  # Lints and formats the code with Standard Ruby.
  gem "standard", require: false
end
