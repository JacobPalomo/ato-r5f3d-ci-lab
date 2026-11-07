# frozen_string_literal: true
require 'securerandom'
raise 'REFUSED_NO_GITHUB_CI' unless ENV['R5F3G_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_DATABASE' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED_WRONG_HOST' unless ENV['POSTGRES_HOST'] == 'postgres'
ActiveJob::Base.queue_adapter = :test
conn = ActiveRecord::Base.connection
%w[ato_ci_r5f3g_guards ato_ci_r5f3g_receipts].each do |table|
  raise "REFUSED_EXISTING_TABLE_#{table}" if conn.data_source_exists?(table)
end
conn.create_table(:ato_ci_r5f3g_guards) do |t|
  t.bigint :conversation_id, null: false
  t.integer :epoch, null: false
  t.string :owner, null: false
end
conn.add_index :ato_ci_r5f3g_guards, :conversation_id, unique: true
conn.create_table(:ato_ci_r5f3g_receipts) do |t|
  t.bigint :conversation_id, null: false
  t.string :delivery_key, null: false
  t.string :payload_hash, null: false
  t.bigint :message_id, null: false
end
conn.add_index :ato_ci_r5f3g_receipts, [:conversation_id, :delivery_key], unique: true,
               name: 'ato_ci_r5f3g_unique_delivery'
class AtoCiR5f3gSetupGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_guards'
end
account = Account.create!(name: 'ATO R5F3G synthetic isolated')
channel = Channel::Api.create!(account: account)
inbox = Inbox.create!(account: account, channel: channel, name: 'ATO R5F3G CI-only', enable_auto_assignment: false)
contact = Contact.create!(account: account, name: 'Synthetic CI Visitor', identifier: "r5f3g-#{SecureRandom.hex(8)}")
contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: "r5f3g-#{SecureRandom.hex(8)}")
conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
AtoCiR5f3gSetupGuard.create!(conversation_id: conversation.id, epoch: 1, owner: 'bot')
raise 'CI_NOT_API_CHANNEL' unless conversation.inbox.channel_type == 'Channel::Api'
puts "R5F3G_FIXTURE_ID=#{conversation.id}"
