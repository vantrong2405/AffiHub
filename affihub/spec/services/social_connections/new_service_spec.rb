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

    it "returns YouTube setup availability from its own provider configuration" do
      service = SocialConnections::NewService.new(provider: "youtube")

      expect(service.call).to eq(true)
      expect(service.provider_configured).to eq(true)
    end

    it "returns Instagram setup as unavailable when Facebook Login for Business has no config ID" do
      configuration = SocialConnections::ProviderConfiguration.for(:instagram).deep_dup
      configuration[:authorization_params][:config_id] = ""
      allow(SocialConnections::ProviderConfiguration).to receive(:for).with("instagram").and_return(configuration)
      service = SocialConnections::NewService.new(provider: "instagram")

      expect(service.call).to eq(true)
      expect(service.provider_configured).to eq(false)
    end
  end
end
