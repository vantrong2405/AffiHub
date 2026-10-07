require "rails_helper"

RSpec.describe "SocialConnections::CreateService", type: :service do
  describe "#call" do
    it "returns a random session-bound state and an allowlisted authorization URL" do
      session = {}
      service = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)

      service.call

      expect(service).to be_success
      expect(service.authorization_url).to start_with("https://www.facebook.com/")
      expect(session).to have_key("social_oauth_attempts")
    end

    it "returns a distinct state for every authorization attempt" do
      session = {}
      first = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      second = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      first.call
      second.call

      expect(first.state).not_to eq(second.state)
    end
  end
end
