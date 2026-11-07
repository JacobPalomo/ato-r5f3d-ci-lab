# frozen_string_literal: true
# Synthetic-only CI endpoint. NEVER install on Chatwoot operational services.
require 'json'
require 'digest'

class AtoCiR5f3j2Authority < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_authorities'
end
class AtoCiR5f3j2Receipt < ActiveRecord::Base
  self.table_name = 'ato_ci_r5f3j2_receipts'
end

class AtoCiR5f3j2OutboundController < ActionController::API
  class Reject < StandardError
    attr_reader :reason, :status_code
    def initialize(status_code, reason)
      @status_code = status_code
      @reason = reason
      super(reason)
    end
  end

  ALLOWED_FIELDS = %w[account_id ato_v06_claim_id content content_attributes conversation_id delivery_key event_id message_type private].freeze
  UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  def create
    expected = ENV.fetch('R5F3J2_TOKEN')
    received = request.headers['X-Ato-R5f3j-Token'].to_s
    return render(json: { ok: false, reason: 'unauthorized' }, status: 401) unless
      received.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(received, expected)

    raw = request.raw_post
    raise Reject.new(413, 'bad_size') if raw.bytesize > 8192
    data = JSON.parse(raw)
    validate!(data)
    digest = Digest::SHA256.hexdigest(JSON.generate([data['content'], 'outgoing', false, { 'ato_automated' => true }]))
    result = nil

    AtoCiR5f3j2Authority.transaction do
      authority = AtoCiR5f3j2Authority.lock.find_by(event_id: data['event_id'])
      raise Reject.new(409, 'unknown_authority') unless authority && authority.account_id == data['account_id'] && authority.conversation_id == data['conversation_id']
      raise Reject.new(409, 'human_takeover') unless authority.owner == 'bot'
      raise Reject.new(409, 'stale_claim') unless authority.event_status == 'processing' && authority.claim_id == data['ato_v06_claim_id']

      conversation = Conversation.find_by(id: authority.conversation_id, account_id: authority.account_id)
      raise Reject.new(409, 'unknown_authority') unless conversation && conversation.account.name == 'ATO R5F3J2 synthetic isolated' &&
                                                       conversation.inbox.channel_type == 'Channel::Whatsapp'
      receipt = AtoCiR5f3j2Receipt.find_by(conversation_id: authority.conversation_id, delivery_key: data['delivery_key'])
      if receipt
        raise Reject.new(409, 'idempotency_conflict') unless receipt.event_id == authority.event_id && receipt.payload_hash == digest
        result = { code: 200, duplicate: true, message_id: receipt.message_id }
      else
        msg = Messages::MessageBuilder.new(nil, conversation, {
          content: data['content'], private: false, message_type: 'outgoing',
          content_attributes: { 'ato_automated' => true }
        }).perform
        raise 'CI_NATIVE_MESSAGE_FAILED' unless msg.persisted? && msg.outgoing? && !msg.private?
        AtoCiR5f3j2Receipt.create!(event_id: authority.event_id, conversation_id: conversation.id,
          message_id: msg.id, delivery_key: data['delivery_key'], payload_hash: digest,
          epoch: authority.epoch, state: 'pending', attempts: 0)
        result = { code: 201, duplicate: false, message_id: msg.id }
      end
    end

    # A durable pending receipt exists before Redis enqueue. Enqueue failure is a
    # recoverable 503, NOT an invitation to create a second native message.
    enqueue_if_pending(result.fetch(:message_id))
    render json: { ok: true, processed: true, persisted: true, duplicate: result.fetch(:duplicate),
                   message_id: result.fetch(:message_id) }, status: result.fetch(:code)
  rescue JSON::ParserError
    render json: { ok: false, processed: false, reason: 'invalid_json' }, status: 400
  rescue Reject => e
    render json: { ok: false, processed: false, persisted: false, reason: e.reason }, status: e.status_code
  rescue Redis::BaseError, Sidekiq::Shutdown => e
    Rails.logger.warn "R5F3J2_CI_ENQUEUE_UNAVAILABLE: #{e.class}"
    render json: { ok: false, processed: false, persisted: true, reason: 'enqueue_unavailable' }, status: 503
  end

  private

  def validate!(d)
    raise Reject.new(422, 'invalid_request') unless d.instance_of?(Hash) && d.keys.sort == ALLOWED_FIELDS
    %w[account_id conversation_id event_id].each do |key|
      raise Reject.new(422, 'invalid_request') unless d[key].instance_of?(Integer) && d[key].positive?
    end
    raise Reject.new(422, 'invalid_claim') unless d['ato_v06_claim_id'].is_a?(String) && UUID_RE.match?(d['ato_v06_claim_id'])
    raise Reject.new(422, 'invalid_delivery_key') unless d['delivery_key'] == "ato-v06:e#{d['event_id']}:public-reply"
    raise Reject.new(422, 'unsupported_effect') unless d['message_type'] == 'outgoing' && d['private'].equal?(false) &&
                                                      d['content_attributes'] == { 'ato_automated' => true }
    raise Reject.new(422, 'invalid_content') unless d['content'].instance_of?(String) && d['content'].length.between?(1, 1000)
  end

  def enqueue_if_pending(message_id)
    return unless AtoCiR5f3j2Receipt.where(message_id: message_id, state: 'pending').exists?

    job = SendReplyJob.new(message_id)
    job.queue_name = 'ato_ci_r5f3j2'
    ActiveJob::QueueAdapters::SidekiqAdapter.new.enqueue(job)
    AtoCiR5f3j2Receipt.where(message_id: message_id, state: 'pending').update_all(state: 'queued')
  end
end
