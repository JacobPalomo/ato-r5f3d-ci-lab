# frozen_string_literal: true
require 'json'
raise 'REFUSED_NO_CI' unless ENV['CI'] == 'true' && ENV['R5F3H_ENABLED'] == 'true'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED_WRONG_HOST' unless ENV['POSTGRES_HOST'] == 'postgres'
class AtoCiR5f3hVerifyGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_guards'
end
class AtoCiR5f3hVerifyReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_receipts'
end
a = Integer(ENV.fetch('R5F3H_BOT_FIRST_ID'))
b = Integer(ENV.fetch('R5F3H_HUMAN_FIRST_ID'))
raise 'BAD_IDS' unless a.positive? && b.positive? && a != b
guards = AtoCiR5f3hVerifyGuard.where(conversation_id: [a,b])
raise 'WRONG_GUARDS' unless guards.count == 2 && guards.all? { |g| g.owner == 'human' && g.epoch == 2 }
notes = Message.where(conversation_id: [a,b], private: true, message_type: :outgoing)
humans = Message.where(conversation_id: [a,b], private: false, message_type: :outgoing, sender_type: 'User')
receipts = AtoCiR5f3hVerifyReceipt.where(conversation_id: [a,b])
raise 'WRONG_NOTES' unless notes.count == 1 && notes.first.conversation_id == a
raise 'WRONG_HUMANS' unless humans.count == 2 && humans.pluck(:conversation_id).sort == [a,b].sort
raise 'WRONG_RECEIPTS' unless receipts.count == 1 && receipts.first.conversation_id == a &&
                              receipts.first.message_id == notes.first.id
raise 'EXTRA_MESSAGES' unless Message.where(conversation_id: [a,b]).count == 3
puts 'R5F3H_VERIFY_JSON=' + JSON.generate({
  native_agent_messages: 2, bot_private_notes: 1,
  unique_receipts: 1, guards_human: 2, no_bot_after_takeover: true
})
