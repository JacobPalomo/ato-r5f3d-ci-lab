# frozen_string_literal: true
# R5F-3E: real Chatwoot model writes with synthetic data in an ephemeral CI DB.
# NOT a product patch, NOT an HTTP API, NOT a WhatsApp sending test.
# Fail closed unless launched by the guarded CI workflow.
require 'json'
require 'digest'
require 'securerandom'

raise 'REFUSED: no isolated R5F-3E CI marker' unless ENV['R5F3E_ENABLED'] == 'true'
raise 'REFUSED: wrong Rails environment' unless Rails.env.production?
raise 'REFUSED: forbidden database' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED: unexpected database host' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'REFUSED: unexpected Redis host' unless ENV['REDIS_URL'] == 'redis://redis:6379'

# Prevent job execution/dispatch: no Sidekiq worker starts and no provider is called.
ActiveJob::Base.queue_adapter = :test

connection = ActiveRecord::Base.connection
%w[accounts channel_api inboxes contacts contact_inboxes conversations messages].each do |table|
  raise "MISSING_CHATWOOT_TABLE: #{table}" unless connection.data_source_exists?(table)
end
%w[ato_ci_r5f3e_receipts ato_ci_r5f3e_guards].each do |table|
  raise "REFUSED: leftover synthetic test table #{table}" if connection.data_source_exists?(table)
end

connection.create_table :ato_ci_r5f3e_guards do |t|
  t.bigint :conversation_id, null: false
  t.integer :epoch, null: false, default: 1
  t.string :owner, null: false, default: 'bot'
end
connection.add_index :ato_ci_r5f3e_guards, :conversation_id, unique: true,
                     name: 'ato_ci_r5f3e_guards_unique_conversation'
connection.create_table :ato_ci_r5f3e_receipts do |t|
  t.bigint :conversation_id, null: false
  t.string :delivery_key, null: false
  t.string :payload_hash, null: false
  t.bigint :message_id, null: false
end
connection.add_index :ato_ci_r5f3e_receipts, [:conversation_id, :delivery_key], unique: true,
                     name: 'ato_ci_r5f3e_receipts_unique_key'

class AtoCiR5f3eGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3e_guards'
end
class AtoCiR5f3eReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3e_receipts'
end

class R5f3eRejected < StandardError; end
class R5f3eConflict < StandardError; end

# This is an in-runner protocol proof, NOT wired into the Chatwoot HTTP controller.
# Both receipt and the native MessageBuilder write participate in one local DB transaction.
def protected_note(conversation, key:, text:, epoch:)
  digest = Digest::SHA256.hexdigest(text)
  AtoCiR5f3eGuard.transaction do
    guard = AtoCiR5f3eGuard.lock.find_by!(conversation_id: conversation.id)
    raise R5f3eRejected, 'stale_claim' unless guard.owner == 'bot' && guard.epoch == epoch

    prior = AtoCiR5f3eReceipt.find_by(conversation_id: conversation.id, delivery_key: key)
    if prior
      raise R5f3eConflict, 'delivery_key_payload_conflict' unless prior.payload_hash == digest
      return [prior.message_id, 'replayed']
    end
    message = Messages::MessageBuilder.new(nil, conversation,
      {content: text, private: true, message_type: 'outgoing'}).perform
    AtoCiR5f3eReceipt.create!(conversation_id: conversation.id,
      delivery_key: key, payload_hash: digest, message_id: message.id)
    [message.id, 'created']
  end
end

# Unique, synthetic records. The entire CI database is destroyed afterward.
account = Account.create!(name: 'ATO R5F3E CI synthetic')
channel = Channel::Api.create!(account: account)
inbox = Inbox.create!(account: account, channel: channel,
                      name: 'ATO R5F3E CI', enable_auto_assignment: false)
contact = Contact.create!(account: account, name: 'Synthetic CI Visitor',
                          identifier: "ci-#{SecureRandom.hex(8)}")
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox,
                                    source_id: "r5f3e-ci-#{SecureRandom.hex(8)}")
conversation = Conversation.create!(account: account, inbox: inbox,
                                    contact: contact, contact_inbox: contact_inbox)
AtoCiR5f3eGuard.create!(conversation_id: conversation.id, epoch: 1, owner: 'bot')

raise 'WRONG_CHANNEL' unless conversation.inbox.channel_type == 'Channel::Api'
first_id, first_kind = protected_note(conversation, key: 'ci-demo-note-1',
                                     text: 'Nota interna: cotización sintética', epoch: 1)
raise 'FIRST_WRITE_FAILED' unless first_kind == 'created' && Message.exists?(id: first_id, private: true)

replayed_id, replay_kind = protected_note(conversation, key: 'ci-demo-note-1',
                                         text: 'Nota interna: cotización sintética', epoch: 1)
raise 'DUPLICATE_CREATED' unless replay_kind == 'replayed' && replayed_id == first_id

conflict_rejected = false
begin
  protected_note(conversation, key: 'ci-demo-note-1', text: 'Contenido diferente', epoch: 1)
rescue R5f3eConflict
  conflict_rejected = true
end
raise 'CONFLICT_NOT_REJECTED' unless conflict_rejected

# Two threads attempt a NEW delivery key concurrently. Lock is on the same guard row.
thread_results = Array.new(2)
threads = 2.times.map do |index|
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      thread_results[index] = protected_note(conversation, key: 'ci-concurrent-note-2',
        text: 'Nota interna concurrente sintética', epoch: 1)
    end
  end
end
threads.each(&:value)
raise 'CONCURRENCY_NOT_DEDUPED' unless thread_results.map(&:first).uniq.size == 1 &&
  thread_results.map(&:last).sort == %w[created replayed]

# Simulated human takeover uses same guard lock. This does not instrument actual agent UI.
AtoCiR5f3eGuard.transaction do
  guard = AtoCiR5f3eGuard.lock.find_by!(conversation_id: conversation.id)
  guard.update!(owner: 'human', epoch: 2)
end
stale_rejected = false
begin
  protected_note(conversation, key: 'ci-stale-note-3',
                 text: 'Nunca debe aparecer', epoch: 1)
rescue R5f3eRejected
  stale_rejected = true
end
raise 'STALE_NOT_REJECTED' unless stale_rejected

receipt_count = AtoCiR5f3eReceipt.where(conversation_id: conversation.id).count
notes = Message.where(conversation_id: conversation.id, private: true, message_type: :outgoing)
raise 'MESSAGE_ROW_COUNT_INVALID' unless receipt_count == 2 && notes.count == 2
raise 'STALE_MESSAGE_PERSISTED' if Message.where(conversation_id: conversation.id,
                                                  content: 'Nunca debe aparecer').exists?

report = {
  phase: 'R5F-3E',
  mode: 'REAL_CHATWOOT_MODEL_WRITE_CI_ONLY',
  passed: true,
  rails_runtime: true,
  chatwoot_message_builder_executed: true,
  synthetic_private_messages: notes.count,
  unique_receipts: receipt_count,
  concurrent_workers: 2,
  concurrent_duplicate_suppressed: true,
  payload_conflict_rejected: conflict_rejected,
  replay_same_message_id: replayed_id == first_id,
  stale_claim_rejected: stale_rejected,
  job_adapter: 'test',
  actual_human_ui_guard_installed: false,
  rails_http_route_patched: false,
  sidekiq_executed: false,
  whatsapp_provider_tested: false,
  public_demo_deployed: false,
  production_modified: false,
  note: 'Real Chatwoot private message rows; only ephemeral CI; not a customer-facing demo'
}
# No container-side writes to host bind mounts; emit one machine-readable verdict.
puts "R5F3E_RESULT_JSON=#{JSON.generate(report)}"
puts 'PASS R5F-3E REAL_CHATWOOT_PRIVATE_MESSAGE_WRITE'
