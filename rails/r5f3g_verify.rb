# frozen_string_literal: true
require 'json'
raise 'REFUSED_NO_GITHUB_CI' unless ENV['R5F3G_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED_WRONG_HOST' unless ENV['POSTGRES_HOST'] == 'postgres'
class AtoCiR5f3gVerifyGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_guards'
end
class AtoCiR5f3gVerifyReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_receipts'
end
cid = Integer(ENV.fetch('R5F3G_CONVERSATION_ID'))
receipts = AtoCiR5f3gVerifyReceipt.where(conversation_id: cid)
messages = Message.where(conversation_id: cid)
guard = AtoCiR5f3gVerifyGuard.find_by!(conversation_id: cid)
raise 'RECEIPTS_WRONG' unless receipts.count == 2 && receipts.distinct.count(:delivery_key) == 2
raise 'MESSAGES_WRONG' unless messages.count == 2 && messages.where(private: true, message_type: :outgoing).count == 2
raise 'GUARD_WRONG' unless guard.owner == 'human' && guard.epoch == 2
ids = messages.pluck(:id).sort
raise 'RECEIPT_POINTERS_WRONG' unless receipts.pluck(:message_id).sort == ids
puts "R5F3G_VERIFY_JSON=#{JSON.generate({database_receipts: 2, database_private_messages: 2, human_takeover_simulated: true, no_public_message: true})}"
