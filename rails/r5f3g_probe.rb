# frozen_string_literal: true
require 'net/http'
require 'json'

raise 'REFUSED_NO_GITHUB_CI' unless ENV['R5F3G_ENABLED'] == 'true' && ENV['CI'] == 'true'
raise 'REFUSED_UNEXPECTED_URL' unless ENV.fetch('R5F3G_SERVER', '') == 'r5f3g-server'
token = ENV.fetch('R5F3G_INTERNAL_TOKEN')
raise 'REFUSED_MISSING_TOKEN' unless token.length >= 40
cid = Integer(ENV.fetch('R5F3G_CONVERSATION_ID'))
raise 'REFUSED_BAD_CONVERSATION_ID' unless cid.positive?
mode = ENV.fetch('R5F3G_MODE')
raise 'REFUSED_BAD_MODE' unless %w[initial replay takeover].include?(mode)

ROUTE = '/internal/ato/r5f3g/deliver'

def send_request(payload, token:)
  # p_addr=nil disables proxy environment variables: never route internal CI traffic externally.
  client = Net::HTTP.new('r5f3g-server', 3000, nil)
  client.open_timeout = 3
  client.read_timeout = 20
  client.start do |http|
    request = Net::HTTP::Post.new(ROUTE)
    request['Host'] = 'chatwoot.invalid'
    request['Content-Type'] = 'application/json'
    request['X-Ato-Internal-Token'] = token if token
    request.body = JSON.generate(payload)
    response = http.request(request)
    [response.code.to_i, JSON.parse(response.body)]
  end
end

base = {
  conversation_id: cid, delivery_key: 'ci-first', epoch: 1,
  effect_kind: 'private_note', content: 'Nota R5F3G sintetica'
}

case mode
when 'initial'
  unauthorized, = send_request(base, token: nil)
  created_code, created = send_request(base, token: token)
  replay_code, replay = send_request(base, token: token)
  conflict_code, conflict = send_request(base.merge(content: 'Alterada'), token: token)
  wrong_effect_code, = send_request(base.merge(delivery_key: 'ci-public', effect_kind: 'public_message'), token: token)
  raise 'CREATION_FAILED' unless created_code == 201 && created['persisted'] == true && created['duplicate'] == false && created['message_id'].is_a?(Integer)
  raise 'REPLAY_FAILED' unless replay_code == 200 && replay['duplicate'] == true && replay['message_id'] == created['message_id']
  raise 'AUTH_FAILED' unless unauthorized == 401
  raise 'CONFLICT_FAILED' unless conflict_code == 409 && conflict['reason'] == 'idempotency_conflict'
  raise 'PUBLIC_WRITE_ALLOWED' unless wrong_effect_code == 422
  parallel = base.merge(delivery_key: 'ci-parallel', content: 'Nota concurrente sintetica')
  responses = Array.new(2)
  threads = 2.times.map do |i|
    Thread.new { responses[i] = send_request(parallel, token: token) }
  end
  threads.each(&:value)
  raise 'CONCURRENT_DUPLICATE' unless responses.map(&:first).sort == [200, 201] &&
    responses.map { |r| r[1]['message_id'] }.uniq.size == 1
  puts "R5F3G_INITIAL_JSON=#{JSON.generate({unauthorized_401: true, created_201: true, replay_200_same_id: true, conflict_409: true, public_rejected_422: true, concurrency_one_write: true})}"
when 'replay'
  # Must still work after docker compose restart, using the same DB receipt.
  status, data = send_request(base, token: token)
  raise 'RESTART_LOST_RECEIPT' unless status == 200 && data['duplicate'] == true && data['message_id'].is_a?(Integer)
  puts "R5F3G_REPLAY_JSON=#{JSON.generate({after_server_restart_replay_200: true})}"
when 'takeover'
  stale_code, stale = send_request(base.merge(delivery_key: 'ci-stale'), token: token)
  human_code, human = send_request(base.merge(delivery_key: 'ci-human', epoch: 2), token: token)
  raise 'STALE_NOT_REJECTED' unless stale_code == 409 && stale['reason'] == 'stale_claim'
  raise 'HUMAN_NOT_REJECTED' unless human_code == 409 && human['reason'] == 'human_takeover'
  puts "R5F3G_TAKEOVER_JSON=#{JSON.generate({stale_rejected_409: true, human_rejected_409: true})}"
end
