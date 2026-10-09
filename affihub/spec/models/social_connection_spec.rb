require "rails_helper"

RSpec.describe SocialConnection, type: :model do
  describe "status" do
    it "returns the configured connection default" do
      expect(build(:social_connection).status).to eq("connected")
    end
  end

  describe "credential storage" do
    it "returns the decrypted access token while storing ciphertext" do
      social_connection = create(:social_connection, access_token: "facebook-user-token")
      persisted_connection = described_class.find(social_connection.id)

      expect(persisted_connection.access_token).to eq("facebook-user-token")
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("facebook-user-token"))
    end

    it "encrypts access tokens for TikTok connections" do
      connection = create(:social_connection, provider: "tiktok", access_token: "tiktok-user-secret")
      persisted_connection = described_class.find(connection.id)

      expect(persisted_connection.access_token).to eq("tiktok-user-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("tiktok-user-secret"))
    end

    it "encrypts TikTok refresh tokens at rest" do
      connection = create(
        :social_connection,
        provider: "tiktok",
        refresh_token: "tiktok-refresh-secret"
      )
      persisted_connection = described_class.find(connection.id)

      expect(persisted_connection.refresh_token).to eq("tiktok-refresh-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:refresh_token)).not_to match(Regexp.escape("tiktok-refresh-secret"))
    end
  end
end
