require "rails"
require "action_controller/railtie"
require "rails-cloudflare-origin"

# Stand-ins for an app's own middleware, recorded with insert_before 0 from an initializer and from
# an environment file, the two places an app puts middleware it wants at the top of the stack.
class InitializerMiddleware
  def initialize(app) = @app = app
  def call(env) = @app.call(env)
end

class EnvironmentMiddleware
  def initialize(app) = @app = app
  def call(env) = @app.call(env)
end

module Dummy
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path "..", __dir__
    config.eager_load = false
    # Boot warnings go to stderr, where the Railtie test reads them.
    config.logger = ActiveSupport::Logger.new $stderr
    config.credentials.content_path = ENV["DUMMY_CREDENTIALS_PATH"] if ENV["DUMMY_CREDENTIALS_PATH"]
  end
end
