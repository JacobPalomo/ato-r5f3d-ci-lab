# frozen_string_literal: true
# R5F-3H: CI-only hook for the native authenticated Chatwoot agent message path.
# This is not a deployment patch and does not cover every human UI action.
if ENV['R5F3H_ENABLED'] == 'true'
  raise 'REFUSED_R5F3H_NON_CI' unless ENV['CI'] == 'true'
  raise 'REFUSED_R5F3H_NO_BASE_GUARD' unless ENV['R5F3G_ENABLED'] == 'true'
  raise 'REFUSED_R5F3H_WRONG_POSTGRES' unless ENV['POSTGRES_HOST'] == 'postgres'
  raise 'REFUSED_R5F3H_WRONG_REDIS' unless ENV['REDIS_URL'] == 'redis://redis:6379'
  raise 'REFUSED_R5F3H_NO_AGENT_TOKEN' unless ENV.fetch('R5F3H_AGENT_TOKEN', '').size >= 40

  module AtoCiR5f3hHumanMessageHook
    def perform
      # Inspect the authenticated server-side actor, not caller-supplied sender_id.
      return super unless @conversation&.account&.name == 'ATO R5F3H synthetic isolated'
      return super unless @user.is_a?(User) && (@message_type || 'outgoing').to_s == 'outgoing'
      return super if ActiveModel::Type::Boolean.new.cast(@params[:private])
      raise 'ATO_CI_EXPECTED_API_CHANNEL' unless @conversation.inbox.channel_type == 'Channel::Api'
      raise 'ATO_CI_AGENT_CONTEXT_REQUIRED' unless Current.user.is_a?(User) && Current.user.id == @user.id &&
                                                    Current.account&.id == @conversation.account_id &&
                                                    AccountUser.exists?(account_id: @conversation.account_id, user_id: @user.id)

      # The human message and the revocation share the same destination-DB transaction
      # and lock as the CI internal delivery controller.
      AtoCiR5f3gGuard.transaction do
        guard = AtoCiR5f3gGuard.lock.find_by!(conversation_id: @conversation.id)
        raise 'ATO_CI_BAD_GUARD' unless %w[bot human].include?(guard.owner)
        guard.update!(owner: 'human', epoch: guard.epoch + 1) if guard.owner == 'bot'
        super()
      end
    end
  end

  Rails.application.config.after_initialize do
    Messages::MessageBuilder.prepend(AtoCiR5f3hHumanMessageHook)
    ActiveJob::Base.queue_adapter = :test
  end
end
