require "rails_helper"

RSpec.describe "SocialConnections::NewService", type: :service do
  describe "#call" do
    it "returns Facebook setup availability without exposing the app secret" do
      service = SocialConnections::NewService.new(provider: "facebook")

      service.call

      expect(service.provider_configured).to eq(true)
    end

    it "returns a safe error for an unsupported provider" do
      service = SocialConnections::NewService.new(provider: "unknown")

      service.call

      expect(service.errors.full_messages.to_sentence).to eq("Nền tảng này chưa được cấu hình kết nối.")
    end
  end
end
