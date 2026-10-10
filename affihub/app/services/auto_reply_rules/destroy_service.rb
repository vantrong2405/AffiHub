class AutoReplyRules::DestroyService < ApplicationService
  attr_reader :rule

  # Initializes a rule deletion request.
  #
  # @param rule_id [Integer] the rule to delete
  # @return [AutoReplyRules::DestroyService] the configured service
  def initialize(rule_id:)
    @rule_id = rule_id
    super()
  end

  # Deletes a rule and removes its webhook subscription when it was the active default.
  #
  # @return [Boolean] whether deletion and any required subscription change succeeded
  def call
    step_load_rule
    return false unless success?

    step_destroy_rule
    return false unless success?

    step_sync_subscription
    success?
  end

  private

  def step_load_rule
    @rule = AutoReplyRule.find_by(id: @rule_id)
    return step_fail!("Không tìm thấy quy tắc tự trả lời.") unless rule

    @was_active_default = rule.default? && rule.enabled?
    step_succeed!
  end

  def step_destroy_rule
    return step_fail!(rule.errors.full_messages.to_sentence) unless rule.destroy

    step_succeed!
  end

  def step_sync_subscription
    return step_succeed! unless @was_active_default

    service = AutoResponder::SyncSubscriptionService.new(social_destination_id: rule.social_destination_id)
    return step_succeed! if service.call

    step_fail!(service.errors.full_messages.to_sentence)
  end
end
