require "telegram/bot"

class Telegram::Client
  # Sends a text message through the telegram-bot-ruby API client.
  #
  # @param chat_id [String, Integer] the Telegram chat receiving the message
  # @param text [String] the message body
  # @return [Boolean] whether Telegram accepted the message
  def send_message(chat_id:, text:)
    response = step_with_bot_client do |bot|
      bot.api.send_message(chat_id:, text:)
    end

    !!response
  end

  # Retrieves updates with the configured long-poll timeout and optional offset.
  #
  # @param offset [Integer, nil] the next update ID to receive
  # @param timeout [Integer] the long-poll timeout in seconds
  # @return [Array<Telegram::Bot::Types::Update>, false] the received updates or false after an API error
  def get_updates(offset: nil, timeout:)
    parameters = { timeout: }
    parameters[:offset] = offset if offset

    step_with_bot_client do |bot|
      bot.api.get_updates(**parameters)
    end
  end

  private

  def step_with_bot_client
    token = Rails.application.credentials.telegram&.dig(:bot_token)
    return false if token.blank?

    yield Telegram::Bot::Client.new(token)
  rescue StandardError
    Rails.logger.error("Telegram Bot API request failed.")
    false
  end
end
