require "rails_helper"

RSpec.describe "SocialDestination", type: :model do
  describe "status" do
    it "returns the configured destination default" do
      expect(build(:social_destination).status).to eq("connected")
    end
  end

  describe "credential storage" do
    it "returns the decrypted Page token while storing ciphertext" do
      destination = create(:social_destination, access_token: "facebook-page-token")
      persisted_destination = "SocialDestination".constantize.find(destination.id)

      expect(persisted_destination.access_token).to eq("facebook-page-token")
      expect(persisted_destination.read_attribute_before_type_cast(:access_token)).not_to include("facebook-page-token")
    end
  end
end
