class Telegram::Alerts::SendService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys

  # Initializes one operational alert for the configured Telegram chats.
  #
  # @param event [String, Symbol] the configured alert event name
  # @param record [ApplicationRecord, nil] the domain record associated with the alert
  # @param details [Hash] safe event details that do not contain credentials
  # @return [Telegram::Alerts::SendService] the configured alert service
  def initialize(event:, record: nil, details: {})
    @event = event.to_sym
    @record = record
    @details = details.deep_symbolize_keys
    super()
  end

  # Builds and sends one operational alert to every configured chat.
  #
  # @return [Boolean] whether all configured Telegram chats accepted the alert
  def call
    return false unless step_build_message
    return false unless step_send_messages

    step_succeed!
    success?
  end

  private

  def step_build_message
    return false unless CONFIGURATION.fetch(:alert_events).map(&:to_sym).include?(@event)

    @message = case @event
    when :worker_down
      "[AffiHub] Solid Queue không còn worker hoạt động. Hãy kiểm tra tiến trình worker."
    when :publication_failed
      "[AffiHub] Publication ##{@record.id} thất bại tại #{@record.social_destination.name}. Mã lỗi: #{@record.safe_error_code}."
    when :publication_outcome_unknown
      "[AffiHub] Publication ##{@record.id} tại #{@record.social_destination.name} chưa rõ kết quả. Hãy kiểm tra nền tảng trước khi thử lại."
    when :api_error
      "[AffiHub] #{@details.fetch(:integration)} gặp lỗi. Mã lỗi: #{@details.fetch(:safe_error_code)}."
    when :api_rate_limited
      "[AffiHub] #{@details.fetch(:integration)} đã chạm giới hạn. Mã lỗi: #{@details.fetch(:safe_error_code)}."
    when :auto_reply_failed
      "[AffiHub] Auto-reply tại #{@record.social_destination.name} thất bại. Mã lỗi: #{@record.safe_error_code}."
    when :auto_reply_outcome_unknown
      "[AffiHub] Auto-reply tại #{@record.social_destination.name} chưa rõ kết quả. Hãy kiểm tra Meta trước khi thử lại."
    when :sheet_sync_retries_exhausted
      "[AffiHub] Đồng bộ Google Sheets đã hết số lần thử. Mã lỗi: #{@record.safe_error_code}."
    when :auto_publish_succeeded
      "[AffiHub] Publication tự đăng ##{@record.id} đã hoàn tất tại #{@record.social_destination.name}."
    when :auto_publish_failed
      "[AffiHub] Lượt tự đăng Publication ##{@record.id} thất bại tại #{@record.social_destination.name}. Mã lỗi: #{@record.safe_error_code}."
    end

    @message.present?
  end

  def step_send_messages
    chat_ids = CONFIGURATION.fetch(:allowed_chat_ids)
    return false if chat_ids.empty?

    telegram_client = Telegram::Client.new
    results = chat_ids.map do |chat_id|
      telegram_client.send_message(chat_id:, text: @message)
    end
    results.all?
  end
end
