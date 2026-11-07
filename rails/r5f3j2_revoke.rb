# frozen_string_literal: true
require 'json'
require 'securerandom'
raise 'REFUSED_NON_CI' unless ENV['R5F3J2_ENABLED'] == 'true' && ENV['CI'] == 'true'
f = JSON.parse(ENV.fetch('R5F3J2_FIXTURES_JSON'))
class AtoCiR5f3j2RevokeAuthority < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_authorities'
end
AtoCiR5f3j2RevokeAuthority.transaction do
  stale = AtoCiR5f3j2RevokeAuthority.lock.find_by!(event_id: f.dig('scenarios', 'stale', 'event_id'))
  human = AtoCiR5f3j2RevokeAuthority.lock.find_by!(event_id: f.dig('scenarios', 'human', 'event_id'))
  raise 'CI_REVOKE_BAD_STATE' unless [stale, human].all? { |x| x.owner == 'bot' && x.epoch == 1 }
  stale.update!(epoch: 2, claim_id: SecureRandom.uuid)
  human.update!(owner: 'human', epoch: 2, event_status: 'manual_review')
end
puts 'R5F3J2_REVOKE_JSON=' + JSON.generate({ changed_claim: true, human_took_over_before_worker: true })
