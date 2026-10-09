require "rails_helper"

RSpec.describe SocialConnections::TikTok::AccessTokenService, type: :service do
  describe "#call" do
    let(:social_connection) do
      create(
        :social_connection,
        provider: "tiktok",
        external_user_id: "creator-1",
        access_token: "creator-access-token",
        refresh_token: "creator-refresh-token",
        token_expires_at: 1.hour.from_now,
        refresh_token_expires_at: 1.month.from_now,
        scopes: %w[user.info.basic video.publish]
      )
    end
    let(:social_destination) do
      create(
        :social_destination,
        social_connection:,
        provider: "tiktok",
        external_id: "creator-1",
        access_token: "creator-access-token",
        token_expires_at: 1.hour.from_now
      )
    end

    it "returns the saved destination token while it remains outside the refresh buffer" do
      service = described_class.new(social_destination_id: social_destination.id)

      expect(service.call).to eq(true)
      expect(service.access_token).to eq("creator-access-token")
    end

    it "stores rotated tokens and updates the TikTok destination after refresh" do
      social_connection.update!(token_expires_at: 1.minute.ago)
      social_destination.update!(token_expires_at: 1.minute.ago)
      stub_request(:post, "https://open.tiktokapis.com/v2/oauth/token/")
        .with(body: {
          "client_key" => "tiktok-test-client",
          "client_secret" => "tiktok-test-secret",
          "grant_type" => "refresh_token",
          "refresh_token" => "creator-refresh-token"
        })
        .to_return(body: {
          access_token: "rotated-access-token",
          refresh_token: "rotated-refresh-token",
          expires_in: 86_400,
          refresh_expires_in: 31_536_000,
          scope: "user.info.basic,video.publish"
        }.to_json)
      service = described_class.new(social_destination_id: social_destination.id)

      expect(service.call).to eq(true)

      expect(service.access_token).to eq("rotated-access-token")
      expect(social_connection.reload.refresh_token).to eq("rotated-refresh-token")
      expect(social_connection.read_attribute_before_type_cast(:refresh_token)).not_to match(Regexp.escape("rotated-refresh-token"))
      expect(social_destination.reload.access_token).to eq("rotated-access-token")
      expect(social_destination.token_expires_at).to be_within(5.seconds).of(Time.current + 86_400.seconds)
    end

    it "requires TikTok reauthorization when an expired connection has no refresh token" do
      social_connection.update!(token_expires_at: 1.minute.ago, refresh_token: nil)
      social_destination.update!(token_expires_at: 1.minute.ago)
      service = described_class.new(social_destination_id: social_destination.id)

      expect(service.call).to eq(false)

      expect(social_connection.reload.status).to eq("reauth_required")
      expect(social_destination.reload.status).to eq("reauth_required")
    end
  end
end
