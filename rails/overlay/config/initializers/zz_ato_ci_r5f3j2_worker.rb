# frozen_string_literal: true
# Real SendReplyJob + Chatwoot WhatsApp service, fake in-process provider only.
raise 'R5F3J2_WORKER_DISABLED' unless ENV['R5F3J2_ENABLED'] == 'true'
raise 'R5F3J2_NON_CI' unless ENV['CI'] == 'true' && ENV['GITHUB_ACTIONS'] == 'true'
raise 'R5F3J2_WRONG_ROLE' unless ENV['R5F3J2_ROLE'] == 'worker'
raise 'R5F3J2_WRONG_PG' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'R5F3J2_WRONG_REDIS' unless ENV['REDIS_URL'] == 'redis://redis:6379'

module AtoCiR5f3j2OutboundGate
  def perform(message_id)
    message = Message.find(message_id)
    raise 'CI_UNEXPECTED_MESSAGE' unless message.account.name == 'ATO R5F3J2 synthetic isolated'
    raise 'CI_INVALID_CHANNEL' unless message.inbox.channel_type == 'Channel::Whatsapp'
    raise 'CI_INVALID_EFFECT' unless message.outgoing? && !message.private? && message.content_attributes['ato_automated'] == true

    ActiveRecord::Base.transaction do
      receipt = AtoCiR5f3j2WorkerReceipt.lock.find_by!(message_id: message_id)
      authority = AtoCiR5f3j2WorkerAuthority.lock.find_by!(event_id: receipt.event_id)
      receipt.update!(attempts: receipt.attempts + 1)
      # A previously confirmed send remains terminal, even after later human takeover.
      next if receipt.state == 'sent'
      if authority.owner != 'bot' || authority.epoch != receipt.epoch || authority.event_status != 'processing'
        receipt.update!(state: 'blocked_human')
        next
      end

      super
      sink = AtoCiR5f3j2WorkerSink.find_by!(message_id: message_id)
      raise 'CI_MISSING_PROVIDER_RECEIPT' unless message.reload.source_id == sink.provider_id
      receipt.update!(state: 'sent')
    end
  end
end

module AtoCiR5f3j2FakeProvider
  def send_message(recipient, message)
    raise 'CI_FAKE_PROVIDER_WRONG_ACCOUNT' unless message.account.name == 'ATO R5F3J2 synthetic isolated'
    raise 'CI_FAKE_PROVIDER_WRONG_RECIPIENT' unless recipient == '15550100001'
    raise 'CI_FAKE_PROVIDER_UNGUARDED' unless ActiveRecord::Base.connection.transaction_open?
    raise 'CI_FAKE_PROVIDER_INVALID_EFFECT' unless message.content_attributes['ato_automated'] == true
    provider_id = "r5f3j2-sink-#{message.id}"
    record = AtoCiR5f3j2WorkerSink.find_or_create_by!(message_id: message.id) do |sink|
      sink.provider_id = provider_id
    end
    raise 'CI_FAKE_PROVIDER_CONFLICT' unless record.provider_id == provider_id
    record.provider_id
  end
end

Rails.application.config.after_initialize do
  class AtoCiR5f3j2WorkerAuthority < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3j2_authorities'
  end
  class AtoCiR5f3j2WorkerReceipt < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3j2_receipts'
  end
  class AtoCiR5f3j2WorkerSink < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3j2_sink'
  end
  SendReplyJob.prepend(AtoCiR5f3j2OutboundGate)
  Whatsapp::Providers::WhatsappCloudService.prepend(AtoCiR5f3j2FakeProvider)
  ActiveJob::Base.queue_adapter = :sidekiq
end
