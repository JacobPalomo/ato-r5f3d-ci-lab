# frozen_string_literal: true
require 'json'
require 'digest'

# This controller is mounted read-only ONLY into the disposable GitHub CI server.
# No public/outgoing messages; only synthetic private notes for Channel::Api.
class AtoCiR5f3gDeliveriesController < ActionController::API
  class Rejected < StandardError; end
  class Conflict < StandardError; end

  def create
    expected = ENV.fetch('R5F3G_INTERNAL_TOKEN')
    received = request.headers['X-Ato-Internal-Token'].to_s
    authorized = received.bytesize == expected.bytesize &&
                 ActiveSupport::SecurityUtils.secure_compare(received, expected)
    return render json: { persisted: false, reason: 'unauthorized' }, status: 401 unless authorized

    body = request.raw_post
    return render json: { persisted: false, reason: 'invalid_request' }, status: 422 if body.bytesize > 4096
    data = JSON.parse(body)
    return invalid_request unless data.is_a?(Hash) && data.keys.sort == %w[content conversation_id delivery_key effect_kind epoch]
    cid, epoch = data.values_at('conversation_id', 'epoch')
    key, content = data.values_at('delivery_key', 'content')
    unless cid.instance_of?(Integer) && cid.positive? && epoch.instance_of?(Integer) && epoch.positive? &&
           key.is_a?(String) && key.match?(/\Aci-[a-z0-9-]{1,64}\z/) &&
           content.is_a?(String) && content.length.between?(1, 512) &&
           data['effect_kind'] == 'private_note'
      return invalid_request
    end

    digest = Digest::SHA256.hexdigest(JSON.generate([data['effect_kind'], content]))
    message_id, replay = AtoCiR5f3gGuard.transaction do
      guard = AtoCiR5f3gGuard.lock.find_by(conversation_id: cid)
      raise Rejected, 'stale_claim' unless guard && guard.epoch == epoch
      raise Rejected, 'human_takeover' unless guard.owner == 'bot'
      receipt = AtoCiR5f3gReceipt.find_by(conversation_id: cid, delivery_key: key)
      if receipt
        raise Conflict, 'idempotency_conflict' unless receipt.payload_hash == digest
        [receipt.message_id, true]
      else
        conversation = Conversation.find_by(id: cid)
        raise Rejected, 'invalid_conversation' unless conversation && conversation.inbox.channel_type == 'Channel::Api'
        note = Messages::MessageBuilder.new(nil, conversation, {
          content: content, private: true, message_type: 'outgoing'
        }).perform
        raise 'PRIVATE_ASSERTION_FAILED' unless note.persisted? && note.private?
        AtoCiR5f3gReceipt.create!(conversation_id: cid, delivery_key: key,
                                   payload_hash: digest, message_id: note.id)
        [note.id, false]
      end
    end
    render json: { persisted: true, duplicate: replay, message_id: message_id }, status: replay ? 200 : 201
  rescue JSON::ParserError
    render json: { persisted: false, reason: 'invalid_json' }, status: 400
  rescue Rejected, Conflict => e
    render json: { persisted: false, reason: e.message }, status: 409
  end

  private

  def invalid_request
    render json: { persisted: false, reason: 'invalid_request' }, status: 422
  end
end
