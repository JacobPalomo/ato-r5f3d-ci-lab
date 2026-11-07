# frozen_string_literal: true
# Synthetic fixtures for two native authenticated agent/API takeover scenarios.
require 'securerandom'
raise 'REFUSED_NON_CI' unless ENV['R5F3H_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED_WRONG_HOST' unless ENV['POSTGRES_HOST'] == 'postgres'
agent_token = ENV.fetch('R5F3H_AGENT_TOKEN')
raise 'REFUSED_SHORT_AGENT_TOKEN' unless agent_token.size >= 40
ActiveJob::Base.queue_adapter = :test
conn = ActiveRecord::Base.connection
%w[ato_ci_r5f3g_guards ato_ci_r5f3g_receipts].each do |table|
  raise "REFUSED_EXISTING_#{table}" if conn.data_source_exists?(table)
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
class AtoCiR5f3hSetupGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_guards'
end
account = Account.create!(name: 'ATO R5F3H synthetic isolated')
channel = Channel::Api.create!(account: account)
inbox = Inbox.create!(account: account, channel: channel,
                      name: 'ATO R5F3H synthetic inbox', enable_auto_assignment: false)
user = User.create!(name: 'R5F3H Synthetic Agent',
                    email: "ci-#{SecureRandom.hex(8)}@example.invalid",
                    password: "CI-#{SecureRandom.hex(16)}a!1", confirmed_at: Time.current)
AccountUser.create!(account: account, user: user, role: 'administrator')
raise 'MISSING_USER_ACCESS_TOKEN' unless user.reload.access_token
user.access_token.update!(token: agent_token)
raise 'WRONG_TOKEN' unless AccessToken.find_by(token: agent_token)&.owner == user
raise 'ACCOUNT_API_DISABLED' unless account.api_and_webhooks_enabled?

make_conversation = lambda do
  contact = Contact.create!(account: account, name: 'CI Synthetic Visitor',
                            identifier: "ci-r5f3h-#{SecureRandom.hex(8)}")
  contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox,
                                       source_id: "ci-r5f3h-#{SecureRandom.hex(8)}")
  conversation = Conversation.create!(account: account, inbox: inbox,
                                      contact: contact, contact_inbox: contact_inbox)
  AtoCiR5f3hSetupGuard.create!(conversation_id: conversation.id, epoch: 1, owner: 'bot')
  conversation
end
bot_first = make_conversation.call
human_first = make_conversation.call
raise 'BAD_FIXTURE' unless bot_first.id != human_first.id && bot_first.display_id && human_first.display_id
puts "R5F3H_ACCOUNT_ID=#{account.id}"
puts "R5F3H_BOT_FIRST_ID=#{bot_first.id}"
puts "R5F3H_BOT_FIRST_DISPLAY=#{bot_first.display_id}"
puts "R5F3H_HUMAN_FIRST_ID=#{human_first.id}"
puts "R5F3H_HUMAN_FIRST_DISPLAY=#{human_first.display_id}"
