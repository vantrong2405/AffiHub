require "rails_helper"

RSpec.describe "SocialConnections::Youtube::AccessTokenService", type: :service do
  describe "#call" do
    let(:social_connection) do
      create(
        :social_connection,
        provider: "youtube",
        access_token: "expired-youtube-access-token",
        refresh_token: "youtube-refresh-token",
        token_expires_at: 1.minute.ago,
        refresh_token_expires_at: 1.day.from_now,
        scopes: [ "openid", "profile", "https://www.googleapis.com/auth/youtube.upload" ]
      )
    end
    let(:social_destination) do
      create(
        :social_destination,
        social_connection:,
        provider: "youtube",
        external_id: "channel-1",
        access_token: "expired-youtube-access-token"
      )
    end

    it "returns a refreshed access token and persists rotated credentials" do
      client = double("Youtube::Client")
      allow(Youtube::Client).to receive(:new).and_return(client)
      allow(client).to receive(:refresh_token).and_return(
        "access_token" => "refreshed-youtube-access-token",
        "refresh_token" => "rotated-youtube-refresh-token",
        "expires_in" => 3600,
        "refresh_token_expires_in" => 86_400,
        "scope" => "openid profile https://www.googleapis.com/auth/youtube.upload"
      )
      service = SocialConnections::Youtube::AccessTokenService.new(social_destination_id: social_destination.id)

      expect(service.call).to eq(true)

      expect(service.access_token).to eq("refreshed-youtube-access-token")
      expect(social_connection.reload.access_token).to eq("refreshed-youtube-access-token")
      expect(social_connection.refresh_token).to eq("rotated-youtube-refresh-token")
      expect(social_destination.reload.access_token).to eq("refreshed-youtube-access-token")
    end

    it "returns false and marks the connection for reauthorization when Google revokes the refresh token" do
      client = double("Youtube::Client")
      allow(Youtube::Client).to receive(:new).and_return(client)
      allow(client).to receive(:refresh_token).and_raise(Youtube::Client::Error, "invalid_grant")
      service = SocialConnections::Youtube::AccessTokenService.new(social_destination_id: social_destination.id)

      expect(service.call).to eq(false)

      expect(social_connection.reload.status).to eq("reauth_required")
      expect(social_destination.reload.status).to eq("reauth_required")
    end
  end
end
