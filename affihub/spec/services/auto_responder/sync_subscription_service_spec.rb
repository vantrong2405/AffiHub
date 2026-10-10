require "rails_helper"

RSpec.describe AutoResponder::SyncSubscriptionService, type: :service do
  describe "#call" do
    it "returns success and subscribes a Facebook Page when its default rule is enabled" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
      request = stub_request(:post, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "feed",
          "access_token" => "page-access-token"
        })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(request).to have_been_requested.once
    end

    it "returns success and subscribes an Instagram Business account when its default rule is enabled" do
      destination = create(
        :social_destination,
        social_connection: create(:social_connection, provider: "instagram"),
        provider: "instagram",
        external_id: "instagram-business-1"
      )
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
      request = stub_request(:post, "https://graph.facebook.com/v26.0/instagram-business-1/subscribed_apps")
        .with(query: {
          "subscribed_fields" => "comments",
          "access_token" => "page-access-token"
        })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(request).to have_been_requested.once
    end

    it "returns success and removes the Facebook Page subscription when no enabled default rule remains" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      request = stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(request).to have_been_requested.once
    end

    it "returns success and removes the Facebook Page subscription when its default rule is disabled" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm.",
        enabled: false
      )
      request = stub_request(:delete, "https://graph.facebook.com/v26.0/facebook-page-1/subscribed_apps")
        .with(query: { "access_token" => "page-access-token" })
        .to_return(body: { success: true }.to_json)
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(request).to have_been_requested.once
    end
  end
end
