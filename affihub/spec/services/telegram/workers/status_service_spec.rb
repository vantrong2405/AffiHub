require "rails_helper"

RSpec.describe Telegram::Workers::StatusService, type: :service do
  describe "#call" do
    it 'returns unavailable when the Solid Queue worker registry cannot be read' do
      expect(described_class.new.call).to eq(:unavailable)
    end
  end
end
