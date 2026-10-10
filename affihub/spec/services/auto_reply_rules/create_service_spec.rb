require "rails_helper"

RSpec.describe AutoReplyRules::CreateService, type: :service do
  describe "#call" do
    it "returns success and subscribes the Page when creating an enabled default rule" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      request = stub_request(:post, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "feed",
          "access_token" => "page-access-token"
        })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(
        social_destination_id: destination.id,
        attributes: { rule_type: "default", reply_text: "Cảm ơn bạn đã quan tâm." }
      )

      expect(service.call).to eq(true)
      expect(service.rule.enabled).to eq(true)
      expect(request).to have_been_requested.once
    end

    it "returns success without changing webhook subscription when creating a keyword rule" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      service = described_class.new(
        social_destination_id: destination.id,
        attributes: { rule_type: "keyword", keyword: "ho tro", reply_text: "Mình có thể hỗ trợ bạn." }
      )

      expect(service.call).to eq(true)
      expect(service.rule.keyword).to eq("ho tro")
      expect(WebMock).not_to have_requested(:any, %r{\Ahttps://graph\.facebook\.com})
    end

    it "returns failure without saving a second default rule for the same destination" do
      destination = create(:social_destination)
      create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      service = described_class.new(
        social_destination_id: destination.id,
        attributes: { rule_type: "default", reply_text: "Một câu trả lời khác." }
      )

      expect(service.call).to eq(false)
      expect(AutoReplyRule.where(social_destination: destination, rule_type: "default").count).to eq(1)
      expect(WebMock).not_to have_requested(:any, %r{\Ahttps://graph\.facebook\.com})
    end

    it "returns failure and keeps a default rule disabled when Meta does not confirm the subscription" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      stub_request(:post, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "feed",
          "access_token" => "page-access-token"
        })
        .to_return(status: 500, body: { error: { code: 1, message: "Temporarily unavailable" } }.to_json)
      stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(
        social_destination_id: destination.id,
        attributes: { rule_type: "default", reply_text: "Cảm ơn bạn đã quan tâm." }
      )

      expect(service.call).to eq(false)
      expect(service.rule.reload.enabled).to eq(false)
      expect(service.errors.empty?).to eq(false)
    end
  end
end
