# frozen_string_literal: true
# Disposable CI-only Chatwoot extension. NEVER mount this into any live instance.
raise 'R5F3G_DISABLED' unless ENV['R5F3G_ENABLED'] == 'true'
raise 'R5F3G_WRONG_ENV' unless Rails.env.production?
raise 'R5F3G_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'R5F3G_WRONG_REDIS' unless ENV['REDIS_URL'] == 'redis://redis:6379'
raise 'R5F3G_MISSING_TOKEN' unless ENV.fetch('R5F3G_INTERNAL_TOKEN', '').length >= 40

Rails.application.config.after_initialize do
  # Crucial: no Sidekiq process is launched, and callbacks remain in test queues.
  ActiveJob::Base.queue_adapter = :test
  Rails.application.routes.append do
    post '/internal/ato/r5f3g/deliver', to: 'ato_ci_r5f3g_deliveries#create', defaults: { format: :json }
  end
  Rails.application.reload_routes!
end
