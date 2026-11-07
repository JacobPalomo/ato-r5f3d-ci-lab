# frozen_string_literal: true
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'

f = JSON.parse(ENV.fetch('R5F3J2_FIXTURES_JSON'))
mode = ENV.fetch('R5F3J2_MODE')
raise 'BAD_MODE' unless %w[initial revoked].include?(mode)
raise 'BAD_FIXTURE' unless f['account_id'].is_a?(Integer) && f.dig('scenarios', 'sent')
url = URI('http://r5f3j2-server:3000/internal/ato/r5f3j2/outbound')
token = ENV.fetch('R5F3J2_TOKEN')

def request(url, token, data, auth_token: token)
  q = Net::HTTP::Post.new(url)
  q['Host'] = 'chatwoot.invalid'
  q['Content-Type'] = 'application/json'
  q['X-Ato-R5f3j-Token'] = auth_token
  q.body = data.is_a?(String) ? data : JSON.generate(data)
  h = Net::HTTP.new(url.host, url.port, nil)
  h.open_timeout = 4
  h.read_timeout = 15
  response = h.request(q)
  [response.code.to_i, JSON.parse(response.body)]
end

def body(f, kind)
  s = f.fetch('scenarios').fetch(kind)
  id = s.fetch('event_id')
  { account_id: f.fetch('account_id'), conversation_id: s.fetch('conversation_id'), event_id: id,
    ato_v06_claim_id: s.fetch('claim_id'), delivery_key: "ato-v06:e#{id}:public-reply",
    content: "R5F3J2 #{kind} outbound synthetic", message_type: 'outgoing', private: false,
    content_attributes: { ato_automated: true } }
end

if mode == 'initial'
  initial_sent = request(url, token, body(f, 'sent'))
  replay = request(url, token, body(f, 'sent'))
  queued_human = request(url, token, body(f, 'human'))
  conflict_payload = body(f, 'sent').merge(content: 'Changed payload')
  conflict = request(url, token, conflict_payload)
  unauthorized = request(url, token, body(f, 'sent'), auth_token: 'incorrect')
  invalid = request(url, token, body(f, 'sent').merge(private: true))
  raise 'CI_INITIAL_FAILURE' unless initial_sent[0] == 201 && initial_sent[1]['processed'] == true &&
    replay[0] == 200 && replay[1]['duplicate'] == true && replay[1]['message_id'] == initial_sent[1]['message_id'] &&
    queued_human[0] == 201 && queued_human[1]['processed'] == true &&
    conflict == [409, {'ok'=>false, 'processed'=>false, 'persisted'=>false, 'reason'=>'idempotency_conflict'}] &&
    unauthorized[0] == 401 && invalid[0] == 422
  puts 'R5F3J2_INITIAL_JSON=' + JSON.generate({ authorized_201: true, replay_200: true, human_queued_201: true,
    conflict_409: true, unauthorized_401: true, unsupported_422: true })
  puts "R5F3J2_SENT_MESSAGE_ID=#{initial_sent[1].fetch('message_id')}"
  puts "R5F3J2_HUMAN_MESSAGE_ID=#{queued_human[1].fetch('message_id')}"
else
  stale = request(url, token, body(f, 'stale'))
  human = request(url, token, body(f, 'human'))
  raise 'CI_REVOKED_FAILURE' unless stale[0] == 409 && stale[1]['reason'] == 'stale_claim' &&
                                    human[0] == 409 && human[1]['reason'] == 'human_takeover'
  puts 'R5F3J2_REVOKED_JSON=' + JSON.generate({ stale_claim_409: true, human_takeover_409: true })
end
