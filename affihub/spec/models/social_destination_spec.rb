require "rails_helper"

RSpec.describe SocialDestination, type: :model do
  describe "status" do
    it "returns the configured destination default" do
      expect(build(:social_destination).status).to eq("connected")
    end
  end

  describe "credential storage" do
    it "returns the decrypted Page token while storing ciphertext" do
      destination = create(:social_destination, access_token: "facebook-page-token")
      persisted_destination = described_class.find(destination.id)

      expect(persisted_destination.access_token).to eq("facebook-page-token")
      expect(persisted_destination.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("facebook-page-token"))
    end
  end

  describe "TikTok creator destination" do
    it "accepts a TikTok creator destination for its matching connection" do
      connection = create(:social_connection, provider: "tiktok")
      destination = build(:social_destination, social_connection: connection, provider: "tiktok")

      expect(destination).to be_valid
    end

    it "returns false when TikTok creator permissions are checked as Meta Page tasks" do
      expect(described_class.can_create_content?([ "CREATE_CONTENT" ], provider: :tiktok)).to eq(false)
    end
  end
end
