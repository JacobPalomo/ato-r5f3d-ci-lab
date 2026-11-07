# frozen_string_literal: true
require 'securerandom'
require 'json'
raise 'REFUSED_NON_CI' unless ENV['CI'] == 'true' && ENV['R5F3J2_ENABLED'] == 'true'
raise 'REFUSED_WRONG_PG' unless ENV['POSTGRES_HOST'] == 'postgres' &&
                              ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
ActiveJob::Base.queue_adapter = :test
conn = ActiveRecord::Base.connection
%w[ato_ci_r5f3j2_authorities ato_ci_r5f3j2_receipts ato_ci_r5f3j2_sink].each do |table|
  raise "CI_TABLE_ALREADY_EXISTS:#{table}" if conn.data_source_exists?(table)
end
conn.create_table :ato_ci_r5f3j2_authorities do |t|
  t.bigint :event_id, null: false
  t.bigint :account_id, null: false
  t.bigint :conversation_id, null: false
  t.string :claim_id, null: false
  t.integer :epoch, null: false
  t.string :owner, null: false
  t.string :event_status, null: false
end
conn.add_index :ato_ci_r5f3j2_authorities, :event_id, unique: true
conn.add_index :ato_ci_r5f3j2_authorities, :conversation_id, unique: true
conn.create_table :ato_ci_r5f3j2_receipts do |t|
  t.bigint :event_id, null: false
  t.bigint :conversation_id, null: false
  t.bigint :message_id, null: false
  t.string :delivery_key, null: false
  t.string :payload_hash, null: false
  t.integer :epoch, null: false
  t.string :state, null: false
  t.integer :attempts, null: false, default: 0
end
conn.add_index :ato_ci_r5f3j2_receipts, :message_id, unique: true
conn.add_index :ato_ci_r5f3j2_receipts, [:conversation_id, :delivery_key], unique: true, name: 'ato_ci_r5f3j2_delivery_unique'
conn.create_table :ato_ci_r5f3j2_sink do |t|
  t.bigint :message_id, null: false
  t.string :provider_id, null: false
end
conn.add_index :ato_ci_r5f3j2_sink, :message_id, unique: true
conn.add_index :ato_ci_r5f3j2_sink, :provider_id, unique: true
class AtoCiR5f3j2SetupAuthority < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_authorities'
end
account = Account.create!(name: 'ATO R5F3J2 synthetic isolated')
now = Time.current
created = Channel::Whatsapp.insert_all!([{account_id: account.id,
  phone_number: "ci-r5f3j2-#{SecureRandom.hex(8)}", provider: 'whatsapp_cloud',
  provider_config: { source: 'manual_setup_v2', api_key: 'CI_ONLY_NEVER_USE',
                     business_account_id: 'ci-fake', phone_number_id: 'ci-fake' },
  phone_number_health: {}, created_at: now, updated_at: now }], returning: %w[id])
channel = Channel::Whatsapp.find(created.rows.fetch(0).fetch(0))
inbox = Inbox.create!(account: account, channel: channel, name: 'ATO R5F3J2 fake WhatsApp', enable_auto_assignment: false)
contact = Contact.create!(account: account, name: 'CI Synthetic', identifier: "ci-r5f3j2-#{SecureRandom.hex(8)}")
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: '15550100001')
fixtures = {}
%i[sent stale human].each_with_index do |kind, idx|
  conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  Message.create!(account: account, inbox: inbox, conversation: conv, sender: contact,
                  message_type: :incoming, private: false, content: 'Synthetic inbound; no Meta')
  raise 'CI_WINDOW_CLOSED' unless conv.reload.can_reply?
  claim_id = SecureRandom.uuid
  event_id = 10001 + idx
  AtoCiR5f3j2SetupAuthority.create!(event_id: event_id, account_id: account.id,
    conversation_id: conv.id, claim_id: claim_id, epoch: 1, owner: 'bot', event_status: 'processing')
  fixtures[kind] = { event_id: event_id, conversation_id: conv.id, claim_id: claim_id }
end
puts 'R5F3J2_FIXTURES_JSON=' + JSON.generate({ account_id: account.id, scenarios: fixtures })
puts 'R5F3J2_SETUP_JSON=' + JSON.generate({ synthetic_whatsapp: true, isolated_ci: true,
  events: 3, meta_credentials: false })
