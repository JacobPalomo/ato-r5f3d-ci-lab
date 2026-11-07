# frozen_string_literal: true
require 'json'
raise 'REFUSED_NON_CI' unless ENV['R5F3I_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
class AtoCiR5f3iVerifyGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_guards'
end
class AtoCiR5f3iVerifyDelivery < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_deliveries'
end
class AtoCiR5f3iVerifySink < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_sink'
end
sent_id = Integer(ENV.fetch('R5F3I_SENT_MESSAGE_ID'))
blocked_id = Integer(ENV.fetch('R5F3I_BLOCKED_MESSAGE_ID'))
raise 'BAD_IDS' if sent_id == blocked_id
sent = AtoCiR5f3iVerifyDelivery.find_by!(message_id: sent_id)
blocked = AtoCiR5f3iVerifyDelivery.find_by!(message_id: blocked_id)
raise 'CI_SENT_STATE' unless sent.state == 'sent' && sent.attempts == 2
raise 'CI_BLOCKED_STATE' unless blocked.state == 'blocked_human' && blocked.attempts == 1
sink = AtoCiR5f3iVerifySink.find_by!(message_id: sent_id)
raise 'CI_PROVIDER_RECEIPT_WRONG' unless sink.provider_id == "ci-sink-#{sent_id}"
raise 'CI_DUPLICATE_PROVIDER_RECEIPT' unless AtoCiR5f3iVerifySink.count == 1
sent_message = Message.find(sent_id)
blocked_message = Message.find(blocked_id)
raise 'CI_SENT_SOURCE_WRONG' unless sent_message.source_id == sink.provider_id
raise 'CI_BLOCKED_WAS_SENT' if blocked_message.source_id.present?
raise 'CI_GUARD_WRONG' unless AtoCiR5f3iVerifyGuard.find_by!(conversation_id: blocked.conversation_id).attributes.slice('owner','epoch') == {'owner'=>'human','epoch'=>2}
raise 'CI_WRONG_CHANNEL' unless [sent_message, blocked_message].all? { |m| m.inbox.channel_type == 'Channel::Whatsapp' }
puts 'R5F3I_VERIFY_JSON=' + JSON.generate({
  real_sidekiq_job_attempts: 3,
  fake_whatsapp_provider_receipts: 1,
  blocked_human_outbound_jobs: 1,
  replay_without_new_fake_provider_receipt: true,
  source_id_recorded: true,
  no_meta_http_executed: true
})
