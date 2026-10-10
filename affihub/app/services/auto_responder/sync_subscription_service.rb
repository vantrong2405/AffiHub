class AutoResponder::SyncSubscriptionService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :social_destination

  # Initializes webhook subscription synchronization for one social destination.
  #
  # @param social_destination_id [Integer] the destination whose rule controls subscription
  # @return [AutoResponder::SyncSubscriptionService] the configured service
  def initialize(social_destination_id:)
    @social_destination_id = social_destination_id
    super()
  end

  # Enables or removes the provider subscription based on the active default rule.
  #
  # @return [Boolean] whether the provider subscription matches the current rule state
  def call
    step_load_destination
    return false unless success?

    step_sync_subscription
    success?
  end

  private

  def step_load_destination
    @social_destination = SocialDestination.find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích kết nối Meta.") unless social_destination
    return step_fail!("Đích này không hỗ trợ webhook comment.") unless provider_configuration.key?(:comment_webhook_field)

    step_succeed!
  end

  def step_sync_subscription
    response = if step_default_rule_enabled?
      step_subscribe
    else
      step_unsubscribe
    end
    return step_fail!("Meta chưa xác nhận thay đổi webhook.") unless response.fetch("success", false) == true

    step_succeed!
  rescue Meta::Client::Error => error
    step_fail!("Không thể cập nhật webhook Meta (#{error.code}).")
  end

  def step_default_rule_enabled?
    social_destination.auto_reply_rules.exists?(
      rule_type: CONFIGURATION.fetch(:default_rule_type),
      enabled: true
    )
  end

  def step_subscribe
    meta_client.subscribe_to_comment_webhooks(
      external_id: social_destination.external_id,
      page_access_token: social_destination.access_token
    )
  end

  def step_unsubscribe
    meta_client.unsubscribe_from_comment_webhooks(
      external_id: social_destination.external_id,
      page_access_token: social_destination.access_token
    )
  end

  def meta_client
    @meta_client ||= Meta::Client.new(provider: social_destination.provider.to_sym)
  end

  def provider_configuration
    @provider_configuration ||= Rails.application.config_for(:meta).deep_symbolize_keys
      .fetch(:providers)
      .fetch(social_destination.provider.to_sym)
  end
end
