class Telegram::Alerts::EnqueueService < ApplicationService
  # Initializes one asynchronous Telegram alert request.
  #
  # @param event [String, Symbol] the event handled by the alert service
  # @param record [ApplicationRecord, nil] the domain record associated with the alert
  # @param details [Hash] safe event details that do not contain credentials
  # @return [Telegram::Alerts::EnqueueService] the configured enqueue service
  def initialize(event:, record: nil, details: {})
    @event = event.to_s
    @record_type = record&.class&.name
    @record_id = record&.id
    @details = details.deep_symbolize_keys
    super()
  end

  # Enqueues alert delivery without making the domain operation depend on Telegram.
  #
  # @return [Boolean] whether Solid Queue accepted the alert job
  def call
    job = Telegram::Alerts::SendJob.perform_later(@event, @record_type, @record_id, @details)
    return false unless job&.successfully_enqueued?

    step_succeed!
    success?
  rescue StandardError
    Rails.logger.error("Telegram alert could not be queued.")
    false
  end
end
