# frozen_string_literal: true
# Queue real SendReplyJobs; do not start worker until handoff has been recorded.
require 'json'
raise 'REFUSED_NON_CI' unless ENV['R5F3I_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
class AtoCiR5f3iQueueGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_guards'
end
class AtoCiR5f3iQueueDelivery < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_deliveries'
end
bot_id = Integer(ENV.fetch('R5F3I_BOT_ID'))
blocked_id = Integer(ENV.fetch('R5F3I_BLOCKED_ID'))
raise 'REFUSED_BAD_IDS' unless bot_id.positive? && blocked_id.positive? && bot_id != blocked_id
ActiveJob::Base.queue_adapter = :test
messages = {}
{bot: bot_id, blocked: blocked_id}.each do |kind, cid|
  AtoCiR5f3iQueueGuard.transaction do
    guard = AtoCiR5f3iQueueGuard.lock.find_by!(conversation_id: cid)
    raise 'CI_BAD_OWNER' unless guard.owner == 'bot' && guard.epoch == 1
    conversation = Conversation.find(cid)
    raise 'CI_WRONG_ACCOUNT' unless conversation.account.name == 'ATO R5F3I synthetic isolated'
    msg = Messages::MessageBuilder.new(nil, conversation,
          {content: "R5F3I #{kind} outbound synthetic", private: false, message_type: 'outgoing'}).perform
    AtoCiR5f3iQueueDelivery.create!(conversation_id: cid, message_id: msg.id,
       delivery_key: "ci-#{kind}", epoch: guard.epoch, state: 'queued')
    messages[kind] = msg
  end
end
# Human takeover commits while Sidekiq remains STOPPED. Its queued bot job must be blocked.
AtoCiR5f3iQueueGuard.transaction do
  guard = AtoCiR5f3iQueueGuard.lock.find_by!(conversation_id: blocked_id)
  raise 'CI_UNEXPECTED_OWNER' unless guard.owner == 'bot' && guard.epoch == 1
  guard.update!(owner: 'human', epoch: 2)
end
# Only explicit CI jobs go to an isolated queue; other Chatwoot callbacks stay in Test.
ActiveJob::Base.queue_adapter = :sidekiq
messages.each_value { |message| SendReplyJob.set(queue: :ato_ci_r5f3i).perform_later(message.id) }
puts "R5F3I_SENT_MESSAGE_ID=#{messages.fetch(:bot).id}"
puts "R5F3I_BLOCKED_MESSAGE_ID=#{messages.fetch(:blocked).id}"
puts 'R5F3I_ENQUEUE_JSON=' + JSON.generate({sidekiq_send_reply_jobs_queued: 2,
  human_takeover_before_worker: true, synthetic_public_outgoing_messages: 2})
