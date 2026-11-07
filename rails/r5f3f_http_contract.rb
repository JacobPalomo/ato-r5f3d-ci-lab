# frozen_string_literal: true
# R5F-3F: Rack/HTTP contract proof in a disposable Chatwoot Rails process.
# NOT installed in the operational Rails app. NO Sidekiq and NO WhatsApp.
require 'json'
require 'digest'
require 'securerandom'
require 'action_dispatch/testing/integration'

raise 'REFUSED: R5F3F_ENABLED absent' unless ENV['R5F3F_ENABLED'] == 'true'
raise 'REFUSED: not production Rails config' unless Rails.env.production?
raise 'REFUSED: wrong ephemeral DB' unless ActiveRecord::Base.connection.select_value('select current_database()') == 'chatwoot_production'
raise 'REFUSED: wrong postgres host' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'REFUSED: wrong redis host' unless ENV['REDIS_URL'] == 'redis://redis:6379'
R5F3F_SECRET = ENV.fetch('R5F3F_INTERNAL_TOKEN')
raise 'REFUSED: missing ephemeral CI secret' unless R5F3F_SECRET.size >= 40

# Every test message is private and uses a Channel::Api in a disposable database.
# Queued ActiveJob callbacks are never executed; there is no provider transport.
ActiveJob::Base.queue_adapter = :test
connection = ActiveRecord::Base.connection
%w[accounts channel_api inboxes contacts contact_inboxes conversations messages].each do |table|
  raise "MISSING_TABLE: #{table}" unless connection.data_source_exists?(table)
end
%w[ato_ci_r5f3f_guards ato_ci_r5f3f_receipts].each do |table|
  raise "REFUSED: leftover table #{table}" if connection.data_source_exists?(table)
end

connection.create_table :ato_ci_r5f3f_guards do |t|
  t.bigint :conversation_id, null: false
  t.integer :epoch, null: false
  t.string :owner, null: false
end
connection.add_index :ato_ci_r5f3f_guards, :conversation_id, unique: true
connection.create_table :ato_ci_r5f3f_receipts do |t|
  t.bigint :conversation_id, null: false
  t.string :delivery_key, null: false
  t.string :payload_hash, null: false
  t.bigint :message_id, null: false
end
connection.add_index :ato_ci_r5f3f_receipts, [:conversation_id, :delivery_key], unique: true,
                     name: 'ato_ci_r5f3f_unique_delivery'

class AtoCiR5f3fGuard < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3f_guards'
end
class AtoCiR5f3fReceipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3f_receipts'
end
class AtoCiR5f3fRejection < StandardError; end
class AtoCiR5f3fConflict < StandardError; end

class AtoCiR5f3fDeliveriesController < ActionController::API
  def create
    received = request.headers['X-Ato-Internal-Token'].to_s
    expected = ENV.fetch('R5F3F_INTERNAL_TOKEN')
    valid = received.bytesize == expected.bytesize &&
            ActiveSupport::SecurityUtils.secure_compare(received, expected)
    return render json: {persisted: false, reason: 'unauthorized'}, status: 401 unless valid

    body = request.raw_post
    return render json: {persisted: false, reason: 'invalid_request'}, status: 422 if body.bytesize > 4096
    data = JSON.parse(body)
    unless data.is_a?(Hash) && data.keys.sort == %w[content conversation_id delivery_key effect_kind epoch]
      return render json: {persisted: false, reason: 'invalid_request'}, status: 422
    end
    cid = data['conversation_id']
    epoch = data['epoch']
    key = data['delivery_key']
    content = data['content']
    unless cid.is_a?(Integer) && cid.positive? && epoch.is_a?(Integer) && epoch.positive? &&
           key.is_a?(String) && key.match?(/\Aci-[a-z0-9-]{1,64}\z/) &&
           content.is_a?(String) && content.size.between?(1, 512) &&
           data['effect_kind'] == 'private_note'
      return render json: {persisted: false, reason: 'invalid_request'}, status: 422
    end

    request_hash = Digest::SHA256.hexdigest(JSON.generate([data['effect_kind'], content]))
    message_id, duplicate = AtoCiR5f3fGuard.transaction do
      guard = AtoCiR5f3fGuard.lock.find_by(conversation_id: cid)
      raise AtoCiR5f3fRejection, 'stale_claim' unless guard && guard.epoch == epoch
      raise AtoCiR5f3fRejection, 'human_takeover' unless guard.owner == 'bot'
      receipt = AtoCiR5f3fReceipt.find_by(conversation_id: cid, delivery_key: key)
      if receipt
        raise AtoCiR5f3fConflict, 'idempotency_conflict' unless receipt.payload_hash == request_hash
        [receipt.message_id, true]
      else
        conversation = Conversation.find(cid)
        message = Messages::MessageBuilder.new(nil, conversation,
          {content: content, private: true, message_type: 'outgoing'}).perform
        raise 'FAILED_PRIVATE_ASSERTION' unless message.private?
        AtoCiR5f3fReceipt.create!(conversation_id: cid, delivery_key: key,
          payload_hash: request_hash, message_id: message.id)
        [message.id, false]
      end
    end
    render json: {persisted: true, duplicate: duplicate, message_id: message_id},
           status: duplicate ? 200 : 201
  rescue JSON::ParserError
    render json: {persisted: false, reason: 'invalid_json'}, status: 400
  rescue AtoCiR5f3fRejection => e
    render json: {persisted: false, reason: e.message}, status: 409
  rescue AtoCiR5f3fConflict => e
    render json: {persisted: false, reason: e.message}, status: 409
  end
end

# Add a temporary route in THIS Rails runner only. This proves ActionDispatch
# routing plus controller response; it does NOT patch a deployed Chatwoot server.
Rails.application.routes.append do
  post '/internal/ato/r5f3f/deliver', to: 'ato_ci_r5f3f_deliveries#create'
end
Rails.application.reload_routes!

account = Account.create!(name: 'ATO R5F3F synthetic')
channel = Channel::Api.create!(account: account)
inbox = Inbox.create!(account: account, channel: channel, name: 'R5F3F CI only',
                      enable_auto_assignment: false)
contact = Contact.create!(account: account, name: 'CI Anonymous',
                          identifier: "r5f3f-#{SecureRandom.hex(8)}")
ci = ContactInbox.create!(contact: contact, inbox: inbox,
                          source_id: "r5f3f-#{SecureRandom.hex(8)}")
conversation = Conversation.create!(account: account, inbox: inbox,
                                    contact: contact, contact_inbox: ci)
AtoCiR5f3fGuard.create!(conversation_id: conversation.id, epoch: 1, owner: 'bot')
raise 'WRONG_CHANNEL' unless conversation.inbox.channel_type == 'Channel::Api'

route_path = '/internal/ato/r5f3f/deliver'
call = lambda do |data, token: R5F3F_SECRET|
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! 'chatwoot.invalid'
  headers = {'CONTENT_TYPE' => 'application/json'}
  headers['HTTP_X_ATO_INTERNAL_TOKEN'] = token if token
  session.post(route_path, params: JSON.generate(data), headers: headers)
  [session.response.status, JSON.parse(session.response.body)]
end
base = {conversation_id: conversation.id, delivery_key: 'ci-first',
        epoch: 1, effect_kind: 'private_note', content: 'Nota interna de prueba R5F3F'}

unauth_status, = call.call(base, token: nil)
raise 'UNAUTHENTICATED_REQUEST_ACCEPTED' unless unauth_status == 401
first_status, first = call.call(base)
raise 'INITIAL_HTTP_WRITE_FAILED' unless first_status == 201 && first['persisted'] == true && first['duplicate'] == false
same_status, same = call.call(base)
raise 'HTTP_REPLAY_FAILED' unless same_status == 200 && same['duplicate'] == true && same['message_id'] == first['message_id']
conflict_status, conflict = call.call(base.merge(content: 'Contenido alterado'))
raise 'HTTP_HASH_CONFLICT_NOT_REJECTED' unless conflict_status == 409 && conflict['reason'] == 'idempotency_conflict'

# Two independent HTTP request sessions race on the same delivery key.
concurrent = base.merge(delivery_key: 'ci-concurrent', content: 'Nota concurrente R5F3F')
results = Array.new(2)
threads = 2.times.map do |i|
  Thread.new { ActiveRecord::Base.connection_pool.with_connection { results[i] = call.call(concurrent) } }
end
threads.each(&:value)
raise 'HTTP_CONCURRENT_FAILED' unless results.map(&:first).sort == [200, 201] &&
  results.map { |r| r[1]['message_id'] }.uniq.size == 1

AtoCiR5f3fGuard.transaction do
  guard = AtoCiR5f3fGuard.lock.find_by!(conversation_id: conversation.id)
  guard.update!(epoch: 2, owner: 'human')
end
stale_status, stale = call.call(base.merge(delivery_key: 'ci-stale'))
raise 'HTTP_STALE_ACCEPTED' unless stale_status == 409 && stale['reason'] == 'stale_claim'
human_status, human = call.call(base.merge(delivery_key: 'ci-human', epoch: 2))
raise 'HTTP_HUMAN_ACCEPTED' unless human_status == 409 && human['reason'] == 'human_takeover'
public_status, = call.call(base.merge(delivery_key: 'ci-public', effect_kind: 'public_message'))
raise 'PUBLIC_WRITE_ACCEPTED' unless public_status == 422

receipt_count = AtoCiR5f3fReceipt.where(conversation_id: conversation.id).count
notes = Message.where(conversation_id: conversation.id, private: true, message_type: :outgoing)
raise 'RECEIPTS_OR_NOTES_WRONG' unless receipt_count == 2 && notes.count == 2
raise 'STALE_OR_PUBLIC_PERSISTED' if Message.where(conversation_id: conversation.id,
  content: ['Contenido alterado']).exists?

report = {
  phase: 'R5F-3F', mode: 'RAILS_HTTP_IN_PROCESS_SYNTHETIC_CI', passed: true,
  rails_runtime: true, rails_http_route_runtime_injected: true,
  persistent_http_route_installed: false,
  chatwoot_message_builder_executed: true,
  http_unauthorized_rejected: unauth_status == 401,
  http_created_201: first_status == 201,
  http_replay_same_message_id: same['message_id'] == first['message_id'],
  http_payload_conflict_rejected: conflict_status == 409,
  http_concurrent_duplicate_suppressed: results.map(&:first).sort == [200, 201],
  http_stale_claim_rejected: stale_status == 409,
  http_human_takeover_rejected: human_status == 409,
  public_message_rejected: public_status == 422,
  synthetic_private_messages: notes.count,
  unique_receipts: receipt_count,
  job_adapter: 'test', sidekiq_executed: false, whatsapp_provider_tested: false,
  actual_human_ui_guard_installed: false,
  production_modified: false, public_demo_deployed: false,
  note: 'In-process Rails HTTP contract only; not a deployed endpoint, bot, or WhatsApp delivery.'
}
puts "R5F3F_RESULT_JSON=#{JSON.generate(report)}"
puts 'PASS R5F-3F RAILS_HTTP_IN_PROCESS_SYNTHETIC_CI'
