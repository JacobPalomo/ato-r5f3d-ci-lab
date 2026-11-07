# frozen_string_literal: true
raise 'R5F3J2_SERVER_DISABLED' unless ENV['R5F3J2_ENABLED'] == 'true'
raise 'R5F3J2_NON_CI' unless ENV['CI'] == 'true' && ENV['GITHUB_ACTIONS'] == 'true'
raise 'R5F3J2_WRONG_ROLE' unless ENV['R5F3J2_ROLE'] == 'http'
raise 'R5F3J2_WRONG_PG' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'R5F3J2_WRONG_REDIS' unless ENV['REDIS_URL'] == 'redis://redis:6379'
raise 'R5F3J2_MISSING_TOKEN' unless ENV.fetch('R5F3J2_TOKEN', '').length >= 40
Rails.application.config.after_initialize do
  # Rails callbacks remain in Test queues; only the explicitly authorized
  # SendReplyJob is sent to the Sidekiq adapter's isolated queue.
  ActiveJob::Base.queue_adapter = :test
  Rails.application.routes.append do
    post '/internal/ato/r5f3j2/outbound', to: 'ato_ci_r5f3j2_outbound#create', defaults: { format: :json }
  end
  Rails.application.reload_routes!
end
