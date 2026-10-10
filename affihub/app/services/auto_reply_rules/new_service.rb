class AutoReplyRules::NewService < ApplicationService
  META_CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys
  PROVIDERS = META_CONFIGURATION.fetch(:providers).filter_map do |provider, configuration|
    provider.to_s if configuration.key?(:comment_webhook_field)
  end.freeze
  DESTINATION_CONNECTED_STATUS = META_CONFIGURATION.fetch(:statuses).fetch(:social_destination)
    .fetch(:values).fetch(:connected)
  CONNECTION_CONNECTED_STATUS = META_CONFIGURATION.fetch(:statuses).fetch(:social_connection)
    .fetch(:values).fetch(:connected)

  attr_reader :destinations, :rule

  # Initializes the connected destinations that can receive automatic replies.
  #
  # @param rule [AutoReplyRule, nil] an unsaved or validation-failed rule to keep in the form
  # @return [AutoReplyRules::NewService] the configured service
  def initialize(rule: nil)
    @rule = rule || AutoReplyRule.new
    super()
  end

  # Loads supported connected destinations for a new auto-reply rule.
  #
  # @return [Boolean] whether the destinations were loaded
  def call
    step_load_destinations
    success?
  end

  private

  def step_load_destinations
    @destinations = SocialDestination.joins(:social_connection).includes(:social_connection)
      .where(
        provider: PROVIDERS,
        status: DESTINATION_CONNECTED_STATUS,
        social_connections: { status: CONNECTION_CONNECTED_STATUS }
      )
      .order(:provider, :name, :id)
      .to_a
    step_succeed!
  end
end
