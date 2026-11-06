Rails.application.configure do
  config.force_ssl = true
  # HostAuthorization joins the stack only when hosts are listed.
  config.hosts << "app.example.com"
  config.middleware.insert_before 0, EnvironmentMiddleware
end
