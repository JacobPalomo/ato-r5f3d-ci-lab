# frozen_string_literal: true
# R5F-3I disposable CI fixture. Never connects to Meta.
require 'securerandom'
raise 'REFUSED_NON_CI' unless ENV['R5F3I_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
ActiveJob::Base.queue_adapter = :test
conn = ActiveRecord::Base.connection
%w[ato_ci_r5f3i_guards ato_ci_r5f3i_deliveries ato_ci_r5f3i_sink].each do |table|
  raise "REFUSED_EXISTING_TABLE:#{table}" if conn.data_source_exists?(table)
end
conn.create_table :ato_ci_r5f3i_guards do |t|
  t.bigint :conversation_id, null: false
  t.integer :epoch, null: false
  t.string :owner, null: false
end
conn.add_index :ato_ci_r5f3i_guards, :conversation_id, unique: true
conn.create_table :ato_ci_r5f3i_deliveries do |t|
  t.bigint :conversation_id, null: false
  t.bigint :message_id, null: false
  t.string :delivery_key, null: false
  t.integer :epoch, null: false
  t.string :state, null: false
  t.integer :attempts, null: false, default: 0
end
conn.add_index :ato_ci_r5f3i_deliveries, :message_id, unique: true
conn.add_index :ato_ci_r5f3i_deliveries, [:conversation_id, :delivery_key], unique: true, name: 'ato_ci_r5f3i_unique_delivery'
conn.create_table :ato_ci_r5f3i_sink do |t|
  t.bigint :message_id, null: false
  t.string :provider_id, null: false
end
conn.add_index :ato_ci_r5f3i_sink, :message_id, unique: true
conn.add_index :ato_ci_r5f3i_sink, :provider_id, unique: true
class AtoCiR5f3iSetupGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3i_guards'
end
account = Account.create!(name: 'ATO R5F3I synthetic isolated')
# insert_all! deliberately bypasses Channel::Whatsapp callbacks/credential checks.
# A real channel creation would synchronize Meta templates and is forbidden here.
now = Time.current
created = Channel::Whatsapp.insert_all!([{account_id: account.id,
  phone_number: "ci-r5f3i-#{SecureRandom.hex(8)}", provider: 'whatsapp_cloud',
  provider_config: {source: 'manual_setup_v2', api_key: 'CI_ONLY_NEVER_USE',
                    business_account_id: 'ci-fake', phone_number_id: 'ci-fake'},
  phone_number_health: {}, created_at: now, updated_at: now}], returning: %w[id])
channel = Channel::Whatsapp.find(created.rows.fetch(0).fetch(0))
inbox = Inbox.create!(account: account, channel: channel, name: 'ATO R5F3I disposable fake WhatsApp',
                      enable_auto_assignment: false)
contact = Contact.create!(account: account, name: 'CI Synthetic Visitor', identifier: "ci-r5f3i-#{SecureRandom.hex(8)}")
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: 'ci-recipient-r5f3i')
conversations = 2.times.map do
  conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
  Message.create!(account: account, inbox: inbox, conversation: conversation, sender: contact,
                  message_type: :incoming, private: false, content: 'Synthetic inbound to open 24h window')
  AtoCiR5f3iSetupGuard.create!(conversation_id: conversation.id, epoch: 1, owner: 'bot')
  raise 'CI_WINDOW_CLOSED' unless conversation.reload.can_reply?
  conversation
end
raise 'CI_INVALID_CHANNEL' unless conversations.all? { |c| c.inbox.channel_type == 'Channel::Whatsapp' }
puts "R5F3I_BOT_ID=#{conversations[0].id}"
puts "R5F3I_BLOCKED_ID=#{conversations[1].id}"
puts 'R5F3I_SETUP_JSON={"synthetic_whatsapp_channel":true,"no_meta_credentials":true}'
