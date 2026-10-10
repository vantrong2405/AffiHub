class Telegram::PollingService
  CONFIGURATION = Rails.application.config_for(:telegram).deep_symbolize_keys
  POLLING_CONFIGURATION = CONFIGURATION.fetch(:polling)

  # Long-polls Telegram updates and checks worker health between responses.
  #
  # @return [Boolean] whether the runner exited after receiving an interrupt
  def call
    return false unless CONFIGURATION.fetch(:enabled)

    @telegram_client = Telegram::Client.new
    @update_offset = nil

    loop do
      updates = @telegram_client.get_updates(
        offset: @update_offset,
        timeout: POLLING_CONFIGURATION.fetch(:timeout_seconds)
      )
      step_process_updates(updates) if updates
      Telegram::Workers::MonitorService.new.call
      sleep(POLLING_CONFIGURATION.fetch(:retry_delay_seconds)) unless updates
    end
  rescue Interrupt
    true
  end

  private

  def step_process_updates(updates)
    updates.each do |update|
      step_process_message(update.message)
      @update_offset = update.update_id + 1
    end
  end

  def step_process_message(message)
    return unless message

    Telegram::Commands::ProcessService.new(chat_id: message.chat.id, command: message.text).call
  rescue StandardError
    Rails.logger.error("Telegram command processing failed.")
    false
  end
end
