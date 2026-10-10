require "rails_helper"

RSpec.describe AutoReplyRules::IndexService, type: :service do
  describe "#call" do
    it "returns the rules for the requested destination in creation order" do
      destination = create(:social_destination)
      first_rule = create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      second_rule = create(
        :auto_reply_rule,
        social_destination: destination,
        rule_type: "keyword",
        keyword: "ho tro"
      )
      create(:auto_reply_rule, rule_type: "default")
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(service.rules).to eq([ first_rule, second_rule ])
    end
  end
end
