# frozen_string_literal: true
raise 'REFUSED_NON_CI' unless ENV['R5F3I_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
class AtoCiR5f3iReplayDelivery < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_deliveries'
end
id = Integer(ENV.fetch('R5F3I_SENT_MESSAGE_ID'))
delivery = AtoCiR5f3iReplayDelivery.find_by!(message_id: id)
raise 'CI_NOT_SENT_YET' unless delivery.state == 'sent' && delivery.attempts == 1
ActiveJob::Base.queue_adapter = :sidekiq
SendReplyJob.set(queue: :ato_ci_r5f3i).perform_later(id)
puts 'R5F3I_REQUEUE_JSON={"replay_job_queued":true}'
