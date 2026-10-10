require "rails_helper"

RSpec.describe "SocialConnections::ShowService", type: :service do
  describe "#call" do
    it "returns the selected profile and its Page destinations" do
      social_connection = create(:social_connection)
      social_destination = create(:social_destination, social_connection:)
      service = SocialConnections::ShowService.new(social_connection_id: social_connection.id)

      service.call

      expect(service.social_destinations).to eq([ social_destination ])
    end

    it "returns a not found error when the profile does not exist" do
      service = SocialConnections::ShowService.new(social_connection_id: -1)

      service.call

      expect(service.errors.full_messages.to_sentence).to eq("Không tìm thấy kết nối này.")
    end
  end
end
