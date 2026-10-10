class AutoReplyRules::IndexService < ApplicationService
  attr_reader :rules

  # Initializes the auto-reply rule list for an optional destination.
  #
  # @param social_destination_id [Integer, nil] an optional destination filter
  # @return [AutoReplyRules::IndexService] the configured service
  def initialize(social_destination_id: nil)
    @social_destination_id = social_destination_id
    super()
  end

  # Loads rules in creation order for stable management screens.
  #
  # @return [Boolean] whether the rule list was loaded
  def call
    step_load_rules
    success?
  end

  private

  def step_load_rules
    @rules = AutoReplyRule.includes(:social_destination).order(:created_at, :id)
    @rules = rules.where(social_destination_id: @social_destination_id) if @social_destination_id.present?
    @rules = rules.to_a
    step_succeed!
  end
end
