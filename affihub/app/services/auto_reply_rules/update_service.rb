class AutoReplyRules::UpdateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :rule

  # Initializes an update request for one auto-reply rule.
  #
  # @param rule_id [Integer] the rule to update
  # @param attributes [Hash] permitted rule fields
  # @return [AutoReplyRules::UpdateService] the configured service
  def initialize(rule_id:, attributes:)
    @rule_id = rule_id
    @attributes = attributes.to_h.symbolize_keys
    super()
  end

  # Saves rule changes and updates the provider subscription when default-rule state changes.
  #
  # @return [Boolean] whether the rule update and required subscription change succeeded
  def call
    step_load_rule
    return false unless success?

    step_update_rule
    return false unless success?

    step_sync_subscription
    success?
  end

  private

  def step_load_rule
    @rule = AutoReplyRule.find_by(id: @rule_id)
    return step_fail!("Không tìm thấy quy tắc tự trả lời.") unless rule

    @was_default_rule_enabled = step_default_rule_enabled?
    step_succeed!
  end

  def step_update_rule
    return step_fail!(rule.errors.full_messages.to_sentence) unless rule.update(@attributes)

    step_succeed!
  end

  def step_sync_subscription
    return step_succeed! if @was_default_rule_enabled == step_default_rule_enabled?

    subscription_service = AutoResponder::SyncSubscriptionService.new(
      social_destination_id: rule.social_destination_id
    )
    return step_succeed! if subscription_service.call

    subscription_error = subscription_service.errors.full_messages.to_sentence
    if step_default_rule_enabled?
      rule.update!(enabled: false)
      AutoResponder::SyncSubscriptionService.new(social_destination_id: rule.social_destination_id).call
    end
    step_fail!(subscription_error)
  end

  def step_default_rule_enabled?
    rule.rule_type == CONFIGURATION.fetch(:default_rule_type) && rule.enabled?
  end
end
