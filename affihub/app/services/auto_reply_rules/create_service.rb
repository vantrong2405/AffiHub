class AutoReplyRules::CreateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :rule

  # Initializes a rule creation request for one social destination.
  #
  # @param social_destination_id [Integer] the destination that owns the rule
  # @param attributes [Hash] permitted rule fields
  # @return [AutoReplyRules::CreateService] the configured service
  def initialize(social_destination_id:, attributes:)
    @social_destination_id = social_destination_id
    @attributes = attributes.to_h.symbolize_keys
    super()
  end

  # Persists one rule and synchronizes webhook subscription when it enables auto-reply.
  #
  # @return [Boolean] whether the rule is saved and its required subscription is active
  def call
    step_load_destination
    return false unless success?

    step_create_rule
    return false unless success?

    step_sync_subscription
    success?
  rescue ActiveRecord::RecordNotUnique
    step_fail!("Đích đã có quy tắc trùng lặp.")
  end

  private

  def step_load_destination
    @social_destination = SocialDestination.find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích đăng để cấu hình tự trả lời.") unless @social_destination

    step_succeed!
  end

  def step_create_rule
    @rule = @social_destination.auto_reply_rules.build(@attributes)
    return step_fail!(rule.errors.full_messages.to_sentence) unless rule.save

    step_succeed!
  end

  def step_sync_subscription
    return step_succeed! unless rule.rule_type == CONFIGURATION.fetch(:default_rule_type) && rule.enabled?

    subscription_service = AutoResponder::SyncSubscriptionService.new(social_destination_id: @social_destination.id)
    return step_succeed! if subscription_service.call

    subscription_error = subscription_service.errors.full_messages.to_sentence
    rule.update!(enabled: false)
    AutoResponder::SyncSubscriptionService.new(social_destination_id: @social_destination.id).call
    step_fail!(subscription_error)
  end
end
