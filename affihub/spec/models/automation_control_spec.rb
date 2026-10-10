require "rails_helper"

RSpec.describe AutomationControl, type: :model do
  describe ".current" do
    it 'returns the persisted global control on repeated calls' do
      automation_control = described_class.current

      expect(described_class.current).to eq(automation_control)
    end
  end
end
