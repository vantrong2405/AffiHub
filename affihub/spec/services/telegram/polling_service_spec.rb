require "rails_helper"

RSpec.describe Telegram::PollingService, type: :service do
  describe "#call" do
    it 'returns true after processing the allowlisted message and advancing the next getUpdates offset' do
      telegram_chat = double("Telegram chat", id: 1001)
      telegram_message = double("Telegram message", chat: telegram_chat, text: "/status")
      telegram_update = double("Telegram update", message: telegram_message, update_id: 15)
      telegram_client = instance_double(Telegram::Client)
      command_service = instance_double(Telegram::Commands::ProcessService)
      monitor_service = instance_double(Telegram::Workers::MonitorService)
      allow(Telegram::Client).to receive(:new).and_return(telegram_client)
      expect(telegram_client).to receive(:get_updates).with(offset: nil, timeout: 20).ordered.and_return([ telegram_update ])
      expect(telegram_client).to receive(:get_updates).with(offset: 16, timeout: 20).ordered.and_raise(Interrupt)
      expect(Telegram::Commands::ProcessService).to receive(:new)
        .with(chat_id: 1001, command: "/status")
        .and_return(command_service)
      expect(command_service).to receive(:call).once
      expect(Telegram::Workers::MonitorService).to receive(:new).and_return(monitor_service)
      expect(monitor_service).to receive(:call).once

      expect(described_class.new.call).to eq(true)
    end
  end
end
