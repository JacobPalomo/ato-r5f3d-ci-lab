# frozen_string_literal: true
require 'json'
raise 'REFUSED_NON_CI' unless ENV['R5F3J2_ENABLED'] == 'true' && ENV['CI'] == 'true'
class AtoCiR5f3j2VerifyAuthority < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_authorities'
end
class AtoCiR5f3j2VerifyReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_receipts'
end
class AtoCiR5f3j2VerifySink < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_sink'
end
f = JSON.parse(ENV.fetch('R5F3J2_FIXTURES_JSON'))
sent_id = Integer(ENV.fetch('R5F3J2_SENT_MESSAGE_ID'))
human_id = Integer(ENV.fetch('R5F3J2_HUMAN_MESSAGE_ID'))
queued_stale_id = Integer(ENV.fetch('R5F3J2_QUEUED_STALE_MESSAGE_ID'))
sent = AtoCiR5f3j2VerifyReceipt.find_by!(message_id: sent_id)
human = AtoCiR5f3j2VerifyReceipt.find_by!(message_id: human_id)
queued_stale = AtoCiR5f3j2VerifyReceipt.find_by!(message_id: queued_stale_id)
raise 'CI_EXPECTED_THREE_RECEIPTS' unless AtoCiR5f3j2VerifyReceipt.count == 3
raise 'CI_SENT_NOT_IDEMPOTENT' unless sent.state == 'sent' && sent.attempts == 2
raise 'CI_HUMAN_NOT_BLOCKED' unless human.state == 'blocked_human' && human.attempts == 1
raise 'CI_QUEUED_STALE_NOT_BLOCKED' unless queued_stale.state == 'blocked_stale_claim' && queued_stale.attempts == 1
raise 'CI_BAD_SINK' unless AtoCiR5f3j2VerifySink.count == 1 && AtoCiR5f3j2VerifySink.find_by!(message_id: sent_id).provider_id == "r5f3j2-sink-#{sent_id}"
raise 'CI_BAD_SENT_MESSAGE' unless Message.find(sent_id).source_id == "r5f3j2-sink-#{sent_id}"
raise 'CI_HUMAN_SENT' unless Message.find(human_id).source_id.blank?
raise 'CI_QUEUED_STALE_SENT' unless Message.find(queued_stale_id).source_id.blank?
raise 'CI_WRONG_NATIVE_COUNT' unless Message.where(account_id: f.fetch('account_id'), message_type: :outgoing).count == 3
raise 'CI_HUMAN_AUTHORITY' unless AtoCiR5f3j2VerifyAuthority.find_by!(event_id: f.dig('scenarios', 'human', 'event_id')).owner == 'human'
raise 'CI_STALE_CREATED' if AtoCiR5f3j2VerifyReceipt.exists?(event_id: f.dig('scenarios', 'stale', 'event_id'))
queued_authority = AtoCiR5f3j2VerifyAuthority.find_by!(event_id: f.dig('scenarios', 'queued_stale', 'event_id'))
raise 'CI_SAME_EPOCH_NOT_TESTED' unless queued_authority.epoch == queued_stale.epoch && queued_authority.claim_id != queued_stale.claim_id && queued_authority.owner == 'bot' && queued_authority.event_status == 'processing'
puts 'R5F3J2_VERIFY_JSON=' + JSON.generate({ native_messages_created: 3, sidekiq_attempts: 4,
  provider_fake_receipts: 1, human_job_blocked: true, queued_stale_job_blocked: true, no_duplicate_replay: true,
  no_real_meta: true, production_modified: false })
