# frozen_string_literal: true
raise 'REFUSED_NO_GITHUB_CI' unless ENV['R5F3G_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_WRONG_HOST' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'REFUSED_WRONG_DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
class AtoCiR5f3gTakeoverGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3g_guards'
end
cid = Integer(ENV.fetch('R5F3G_CONVERSATION_ID'))
AtoCiR5f3gTakeoverGuard.transaction do
  row = AtoCiR5f3gTakeoverGuard.lock.find_by!(conversation_id: cid)
  raise 'WRONG_OWNER_OR_EPOCH' unless row.owner == 'bot' && row.epoch == 1
  row.update!(owner: 'human', epoch: 2)
end
puts 'R5F3G_TAKEOVER_SIMULATED=YES'
