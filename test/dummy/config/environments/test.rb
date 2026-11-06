Rails.application.configure do
  config.middleware.insert_before 0, EnvironmentMiddleware
end
