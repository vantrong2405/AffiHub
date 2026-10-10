require "rails_helper"

RSpec.describe AutoReplyRules::ShowService, type: :service do
  describe "#call" do
    it "returns the requested rule" do
      rule = create(:auto_reply_rule)
      service = described_class.new(rule_id: rule.id)

      expect(service.call).to eq(true)
      expect(service.rule).to eq(rule)
    end

    it "returns failure when the requested rule does not exist" do
      service = described_class.new(rule_id: -1)

      expect(service.call).to eq(false)
    end
  end
end
