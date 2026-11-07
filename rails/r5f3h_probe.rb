# frozen_string_literal: true
# Actual HTTP requests to a SEPARATE Rails server in the isolated Docker network.
require 'json'
require 'net/http'
raise 'REFUSED_NO_CI' unless ENV['CI'] == 'true' && ENV['R5F3H_ENABLED'] == 'true'
raise 'REFUSED_WRONG_HOST' unless ENV['R5F3G_SERVER'] == 'r5f3g-server'
mode = ENV.fetch('R5F3H_MODE')
raise 'REFUSED_BAD_MODE' unless %w[initial restart].include?(mode)
account_id = Integer(ENV.fetch('R5F3H_ACCOUNT_ID'))
bot_id = Integer(ENV.fetch('R5F3H_BOT_FIRST_ID'))
bot_display = Integer(ENV.fetch('R5F3H_BOT_FIRST_DISPLAY'))
human_id = Integer(ENV.fetch('R5F3H_HUMAN_FIRST_ID'))
human_display = Integer(ENV.fetch('R5F3H_HUMAN_FIRST_DISPLAY'))
raise 'REFUSED_BAD_IDS' unless [account_id,bot_id,bot_display,human_id,human_display].all?(&:positive?)
internal_token = ENV.fetch('R5F3G_INTERNAL_TOKEN')
agent_token = ENV.fetch('R5F3H_AGENT_TOKEN')
raise 'REFUSED_SHORT_TOKEN' unless internal_token.size >= 40 && agent_token.size >= 40

def call_http(path, payload, token_header, token)
  client = Net::HTTP.new('r5f3g-server', 3000, nil)
  client.open_timeout = 4
  client.read_timeout = 20
  client.start do |http|
    req = Net::HTTP::Post.new(path)
    req['Host'] = 'chatwoot.invalid'
    req['Content-Type'] = 'application/json'
    req[token_header] = token if token
    req.body = JSON.generate(payload)
    response = http.request(req)
    data = JSON.parse(response.body)
    [response.code.to_i, data]
  end
end

bot_call = lambda do |cid, key, epoch|
  call_http('/internal/ato/r5f3g/deliver', {
    conversation_id: cid, delivery_key: key, epoch: epoch,
    effect_kind: 'private_note', content: 'CI bot private note'
  }, 'X-Ato-Internal-Token', internal_token)
end
human_call = lambda do |display|
  # This is Chatwoot's native authenticated message creation endpoint.
  call_http("/api/v1/accounts/#{account_id}/conversations/#{display}/messages", {
    content: 'CI authentic agent outgoing message', message_type: 'outgoing', private: false
  }, 'api_access_token', agent_token)
end

if mode == 'initial'
  first_code, first = bot_call.call(bot_id, 'ci-first', 1)
  raise 'BOT_FIRST_FAILED' unless first_code == 201 && first['persisted'] == true && first['message_id'].is_a?(Integer)
  agent_code, = human_call.call(bot_display)
  raise "NATIVE_AGENT_ROUTE_FAILED_#{agent_code}" unless [200,201].include?(agent_code)
  stale_code, stale = bot_call.call(bot_id, 'ci-late', 1)
  raise 'STALE_NOT_REJECTED' unless stale_code == 409 && stale['reason'] == 'stale_claim'
  owner_code, owner = bot_call.call(bot_id, 'ci-late-owner', 2)
  raise 'HUMAN_NOT_REJECTED' unless owner_code == 409 && owner['reason'] == 'human_takeover'
  agent2_code, = human_call.call(human_display)
  raise "HUMAN_FIRST_ROUTE_FAILED_#{agent2_code}" unless [200,201].include?(agent2_code)
  human_stale_code, human_stale = bot_call.call(human_id, 'ci-human-first', 1)
  raise 'HUMAN_FIRST_BOT_ALLOWED' unless human_stale_code == 409 && human_stale['reason'] == 'stale_claim'
  puts 'R5F3H_INITIAL_JSON=' + JSON.generate({
    native_agent_http_accepted: true, bot_before_human_201: true,
    bot_after_human_stale_409: true, current_epoch_human_409: true,
    human_first_blocks_bot_409: true
  })
else
  a_code, a = bot_call.call(bot_id, 'ci-after-restart-a', 1)
  b_code, b = bot_call.call(human_id, 'ci-after-restart-b', 1)
  raise 'RESTART_LOST_TAKEOVER' unless a_code == 409 && b_code == 409 &&
                                             a['reason'] == 'stale_claim' && b['reason'] == 'stale_claim'
  puts 'R5F3H_RESTART_JSON=' + JSON.generate({after_restart_bot_rejected: true})
end
