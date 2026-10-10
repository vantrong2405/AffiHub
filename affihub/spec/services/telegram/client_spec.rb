require "rails_helper"

RSpec.describe Telegram::Client, type: :service do
  describe "#send_message" do
    it 'returns true when the Telegram Bot API accepts the message' do
      token = "123456:telegram-test-token"
      telegram_api = double("Telegram Bot API", send_message: true)
      telegram_bot = double("Telegram Bot", api: telegram_api)
      allow(Rails.application.credentials).to receive(:telegram).and_return({ bot_token: token })
      allow(Telegram::Bot::Client).to receive(:new).with(token).and_return(telegram_bot)
      client = described_class.new

      expect(client.send_message(chat_id: "1001", text: "Trạng thái hoạt động.")).to eq(true)
      expect(telegram_api).to have_received(:send_message).with(chat_id: "1001", text: "Trạng thái hoạt động.").once
    end

    it 'returns false and logs only a safe message when the Bot API error contains the token' do
      token = "123456:telegram-test-token"
      log_messages = []
      telegram_api = double("Telegram Bot API")
      telegram_bot = double("Telegram Bot", api: telegram_api)
      allow(telegram_api).to receive(:send_message)
        .and_raise(StandardError, "request failed at https://api.telegram.org/bot#{token}/sendMessage")
      allow(Rails.application.credentials).to receive(:telegram).and_return({ bot_token: token })
      allow(Telegram::Bot::Client).to receive(:new).with(token).and_return(telegram_bot)
      allow(Rails.logger).to receive(:error) { |message| log_messages << message }
      client = described_class.new

      expect(client.send_message(chat_id: "1001", text: "Trạng thái hoạt động.")).to eq(false)
      expect(log_messages).to eq([ "Telegram Bot API request failed." ])
      expect(log_messages.join.exclude?(token)).to eq(true)
    end
  end

  describe "#get_updates" do
    it 'returns the updates from the Telegram Bot API using the requested offset and timeout' do
      token = "123456:telegram-test-token"
      updates = [ double("Telegram update") ]
      telegram_api = double("Telegram Bot API", get_updates: updates)
      telegram_bot = double("Telegram Bot", api: telegram_api)
      allow(Rails.application.credentials).to receive(:telegram).and_return({ bot_token: token })
      allow(Telegram::Bot::Client).to receive(:new).with(token).and_return(telegram_bot)
      client = described_class.new

      expect(client.get_updates(offset: 17, timeout: 20)).to eq(updates)
      expect(telegram_api).to have_received(:get_updates).with(offset: 17, timeout: 20).once
    end
  end
end
