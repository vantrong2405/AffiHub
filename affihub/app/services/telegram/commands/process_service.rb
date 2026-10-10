class Telegram::Commands::ProcessService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys

  # Initializes one command received from Telegram.
  #
  # @param chat_id [String, Integer] the chat that sent the command
  # @param command [String] the command text received from Telegram
  # @return [Telegram::Commands::ProcessService] the configured command service
  def initialize(chat_id:, command:)
    @chat_id = chat_id.to_s
    @command = command.to_s.strip
    super()
  end

  # Validates the chat, applies a supported command, and sends its response.
  #
  # @return [Boolean] whether the command was accepted and its response was sent
  def call
    return false unless step_authorize_chat
    return false unless step_find_command
    return false unless step_execute_command
    return false unless step_send_response

    step_succeed!
    success?
  end

  private

  def step_authorize_chat
    CONFIGURATION.fetch(:allowed_chat_ids).map(&:to_s).include?(@chat_id)
  end

  def step_find_command
    @command_name = CONFIGURATION.fetch(:commands).key(@command)
    @command_name.present?
  end

  def step_execute_command
    case @command_name
    when :status
      step_build_status_message
    when :pause_auto_publish
      step_update_automation_control(:auto_publish_paused, true, "Đã tạm dừng tự đăng.")
    when :resume_auto_publish
      step_update_automation_control(:auto_publish_paused, false, "Đã tiếp tục tự đăng.")
    when :pause_auto_reply
      step_update_automation_control(:auto_responder_paused, true, "Đã tạm dừng tự trả lời bình luận.")
    when :resume_auto_reply
      step_update_automation_control(:auto_responder_paused, false, "Đã tiếp tục tự trả lời bình luận.")
    else
      false
    end
  end

  def step_update_automation_control(attribute, value, response)
    AutomationControl.current.update!(attribute => value)
    @response = response
    true
  end

  def step_build_status_message
    @response = [
      "Worker: #{step_worker_status}",
      "Publication đang lên lịch: #{Publication.where(status: CONFIGURATION.dig(:statuses, :publication_scheduled)).count}",
      "Publication chưa rõ kết quả: #{Publication.where(status: CONFIGURATION.dig(:statuses, :publication_outcome_unknown)).count}",
      "Lỗi gần nhất: #{step_latest_error_code}"
    ].join("\n")
  end

  def step_worker_status
    worker_status = Telegram::Workers::StatusService.new.call

    case worker_status
    when :running
      "Đang chạy"
    when :stopped
      "Đã dừng"
    else
      "Chưa thể kiểm tra"
    end
  end

  def step_latest_error_code
    error_records = [
      Publication.where(status: [ CONFIGURATION.dig(:statuses, :publication_failed),
        CONFIGURATION.dig(:statuses, :publication_outcome_unknown) ]),
      AutoReplyEvent.where(status: CONFIGURATION.dig(:statuses, :auto_reply_failed)),
      SheetSync.where(status: CONFIGURATION.dig(:statuses, :sheet_sync_failed))
    ].map { |scope| scope.order(updated_at: :desc, id: :desc).first }.compact

    error_records.max_by(&:updated_at)&.safe_error_code || "Không có"
  end

  def step_send_response
    Telegram::Client.new.send_message(chat_id: @chat_id, text: @response)
  end
end
