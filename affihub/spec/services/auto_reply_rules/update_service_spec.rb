require "rails_helper"

RSpec.describe AutoReplyRules::UpdateService, type: :service do
  describe "#call" do
    it "returns success and subscribes the Page when an inactive default rule is enabled" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      rule = create(:auto_reply_rule, social_destination: destination, rule_type: "default", enabled: false)
      request = stub_request(:post, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "feed",
          "access_token" => "page-access-token"
        })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(rule_id: rule.id, attributes: { enabled: true })

      expect(service.call).to eq(true)
      expect(rule.reload.enabled).to eq(true)
      expect(request).to have_been_requested.once
    end

    it "returns success and removes the Page subscription when an enabled default rule is disabled" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      rule = create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      request = stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(rule_id: rule.id, attributes: { enabled: false })

      expect(service.call).to eq(true)
      expect(rule.reload.enabled).to eq(false)
      expect(request).to have_been_requested.once
    end

    it "returns success without changing webhook subscription when updating a keyword reply" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      rule = create(
        :auto_reply_rule,
        social_destination: destination,
        rule_type: "keyword",
        keyword: "ho tro"
      )
      service = described_class.new(rule_id: rule.id, attributes: { reply_text: "Câu mới." })

      expect(service.call).to eq(true)
      expect(rule.reload.reply_text).to eq("Câu mới.")
      expect(WebMock).not_to have_requested(:any, %r{\Ahttps://graph\.facebook\.com})
    end

    it "returns failure and keeps a default rule disabled when Meta does not confirm the subscription" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      rule = create(:auto_reply_rule, social_destination: destination, rule_type: "default", enabled: false)
      stub_request(:post, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "feed",
          "access_token" => "page-access-token"
        })
        .to_return(status: 500, body: { error: { code: 1, message: "Temporarily unavailable" } }.to_json)
      stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(rule_id: rule.id, attributes: { enabled: true })

      expect(service.call).to eq(false)
      expect(rule.reload.enabled).to eq(false)
      expect(service.errors.empty?).to eq(false)
    end
  end
end
