require "rails_helper"

RSpec.describe AutoReplyRules::DestroyService, type: :service do
  describe "#call" do
    it "returns success and removes the Page subscription when destroying the active default rule" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      rule = create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      request = stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(rule_id: rule.id)

      expect(service.call).to eq(true)
      expect(AutoReplyRule.exists?(rule.id)).to eq(false)
      expect(request).to have_been_requested.once
    end

    it "returns success without changing webhook subscription when destroying a keyword rule" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      rule = create(
        :auto_reply_rule,
        social_destination: destination,
        rule_type: "keyword",
        keyword: "ho tro"
      )
      service = described_class.new(rule_id: rule.id)

      expect(service.call).to eq(true)
      expect(AutoReplyRule.exists?(rule.id)).to eq(false)
      expect(WebMock).not_to have_requested(:any, %r{\Ahttps://graph\.facebook\.com})
    end

    it "returns failure when the rule does not exist" do
      service = described_class.new(rule_id: -1)

      expect(service.call).to eq(false)
    end
  end
end
