# frozen_string_literal: true
raise 'REFUSED_NON_CI' unless ENV['R5F3J2_ENABLED'] == 'true' && ENV['CI'] == 'true'
class AtoCiR5f3j2ReplayReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_receipts'
end
id = Integer(ENV.fetch('R5F3J2_SENT_MESSAGE_ID'))
row = AtoCiR5f3j2ReplayReceipt.find_by!(message_id: id)
raise 'CI_UNSENT' unless row.state == 'sent' && row.attempts == 1
ActiveJob::Base.queue_adapter = :sidekiq
SendReplyJob.set(queue: :ato_ci_r5f3j2).perform_later(id)
puts 'R5F3J2_REPLAY_JSON={"replay_job_queued":true}'
