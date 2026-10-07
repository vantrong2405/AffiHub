require "rails_helper"

RSpec.describe "SocialConnection", type: :model do
  describe "status" do
    it "returns the configured connection default" do
      expect(build(:social_connection).status).to eq("connected")
    end
  end

  describe "credential storage" do
    it "returns the decrypted access token while storing ciphertext" do
      social_connection = create(:social_connection, access_token: "facebook-user-token")
      persisted_connection = "SocialConnection".constantize.find(social_connection.id)

      expect(persisted_connection.access_token).to eq("facebook-user-token")
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to include("facebook-user-token")
    end
  end
end
