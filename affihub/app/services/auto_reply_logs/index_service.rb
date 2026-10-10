class AutoReplyLogs::IndexService < ApplicationService
  attr_reader :events

  # Initializes the auto-reply log list for an optional destination.
  #
  # @param social_destination_id [Integer, nil] an optional destination filter
  # @return [AutoReplyLogs::IndexService] the configured service
  def initialize(social_destination_id: nil)
    @social_destination_id = social_destination_id
    super()
  end

  # Loads comment event logs in newest-first order.
  #
  # @return [Boolean] whether the event list was loaded
  def call
    step_load_events
    success?
  end

  private

  def step_load_events
    @events = AutoReplyEvent.includes(:social_destination).order(created_at: :desc, id: :desc)
    @events = events.where(social_destination_id: @social_destination_id) if @social_destination_id.present?
    @events = events.to_a
    step_succeed!
  end
end
