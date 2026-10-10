class AutoReplyRules::ShowService < ApplicationService
  attr_reader :rule

  # Initializes a read request for one auto-reply rule.
  #
  # @param rule_id [Integer] the rule to load
  # @return [AutoReplyRules::ShowService] the configured service
  def initialize(rule_id:)
    @rule_id = rule_id
    super()
  end

  # Loads one rule for display or editing.
  #
  # @return [Boolean] whether the rule exists
  def call
    step_load_rule
    success?
  end

  private

  def step_load_rule
    @rule = AutoReplyRule.includes(:social_destination).find_by(id: @rule_id)
    return step_fail!("Không tìm thấy quy tắc tự trả lời.") unless rule

    step_succeed!
  end
end
