# frozen_string_literal: true
# CI-only: real Chatwoot SendReplyJob -> Whatsapp service -> synthetic DB sink.
# NEVER install this overlay on a live Chatwoot instance.
raise 'R5F3I_DISABLED' unless ENV['R5F3I_ENABLED'] == 'true'
raise 'R5F3I_NOT_GITHUB_CI' unless ENV['CI'] == 'true' && ENV['GITHUB_ACTIONS'] == 'true'
raise 'R5F3I_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
raise 'R5F3I_WRONG_REDIS' unless ENV['REDIS_URL'] == 'redis://redis:6379'
raise 'R5F3I_UNEXPECTED_ROLE' unless ENV['R5F3I_ROLE'] == 'fake-sink-worker'

# Keep the same destination-database lock for the authorization check and
# synthetic provider event. Sending to a real provider inside such a transaction
# is NOT an approved architecture; the adapter below performs zero network I/O.
module AtoCiR5f3iOutboundGate
  def perform(message_id)
    message = Message.find(message_id)
    raise 'CI_UNEXPECTED_JOB' unless message.account.name == 'ATO R5F3I synthetic isolated'
    raise 'CI_WRONG_CHANNEL' unless message.inbox.channel_type == 'Channel::Whatsapp'
    raise 'CI_WRONG_CONTENT' unless message.outgoing? && !message.private?

    ActiveRecord::Base.transaction do
      row = AtoCiR5f3iGuard.lock.find_by!(conversation_id: message.conversation_id)
      delivery = AtoCiR5f3iDelivery.lock.find_by!(message_id: message.id)
      delivery.update!(attempts: delivery.attempts + 1)
      if row.owner != 'bot' || row.epoch != delivery.epoch
        delivery.update!(state: 'blocked_human')
        next
      end
      next if delivery.state == 'sent'

      super
      sink = AtoCiR5f3iSink.find_by!(message_id: message.id)
      raise 'CI_NOT_ACKNOWLEDGED' unless message.reload.source_id == sink.provider_id
      delivery.update!(state: 'sent')
    end
  end
end

# Intercept at the last boundary of Chatwoot's native WhatsApp pipeline.
# No Meta HTTP call is possible through this method in the disposable worker.
module AtoCiR5f3iFakeWhatsappProvider
  def send_message(recipient, message)
    raise 'CI_FAKE_PROVIDER_UNEXPECTED_ACCOUNT' unless message.account.name == 'ATO R5F3I synthetic isolated'
    raise 'CI_FAKE_PROVIDER_WRONG_CHANNEL' unless message.inbox.channel_type == 'Channel::Whatsapp'
    raise 'CI_FAKE_PROVIDER_WRONG_RECIPIENT' unless recipient == '15550100001'
    raise 'CI_FAKE_PROVIDER_PRIVATE_MESSAGE' if message.private? || !message.outgoing?
    raise 'CI_FAKE_PROVIDER_UNGUARDED_CALL' unless ActiveRecord::Base.connection.transaction_open?

    # Fake sink's unique message_id prevents duplicate *synthetic* observations.
    # It is NOT a Meta idempotency key or an exactly-once guarantee.
    id = "ci-sink-#{message.id}"
    record = AtoCiR5f3iSink.find_or_create_by!(message_id: message.id) do |sink|
      sink.provider_id = id
    end
    raise 'CI_SINK_CONFLICT' unless record.provider_id == id
    record.provider_id
  end
end

Rails.application.config.after_initialize do
  class AtoCiR5f3iGuard < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3i_guards'
  end
  class AtoCiR5f3iDelivery < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3i_deliveries'
  end
  class AtoCiR5f3iSink < ActiveRecord::Base
    self.table_name = 'ato_ci_r5f3i_sink'
  end
  SendReplyJob.prepend(AtoCiR5f3iOutboundGate)
  Whatsapp::Providers::WhatsappCloudService.prepend(AtoCiR5f3iFakeWhatsappProvider)
  ActiveJob::Base.queue_adapter = :sidekiq
end
