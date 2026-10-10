class Telegram::Alerts::SendJob < ApplicationJob
  queue_as :default

  # Sends one queued operational alert to the configured Telegram chats.
  #
  # @param event [String] the configured alert event name
  # @param record_type [String, nil] the supported Active Record class name
  # @param record_id [Integer, nil] the domain record ID
  # @param details [Hash] safe event details that do not contain credentials
  # @return [Boolean] whether all configured chats accepted the alert
  def perform(event, record_type = nil, record_id = nil, details = {})
    record = step_record(record_type, record_id)
    return false if record_type.present? && record.nil?

    Telegram::Alerts::SendService.new(event:, record:, details:).call
  end

  private

  def step_record(record_type, record_id)
    case record_type
    when "Publication"
      Publication.find_by(id: record_id)
    when "AutoReplyEvent"
      AutoReplyEvent.find_by(id: record_id)
    when "SheetSync"
      SheetSync.find_by(id: record_id)
    end
  end
end
