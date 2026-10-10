require "rails_helper"

RSpec.describe "SocialConnections::IndexService", type: :service do
  describe "#call" do
    it "returns connected profiles in reverse creation order" do
      older_connection = create(:social_connection, created_at: 1.day.ago)
      newer_connection = create(:social_connection, created_at: 1.hour.ago)
      service = SocialConnections::IndexService.new

      service.call

      expect(service.social_connections).to eq([ newer_connection, older_connection ])
    end
  end
end
