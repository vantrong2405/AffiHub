require "rails_helper"

RSpec.describe Publications::PublisherResolver, type: :service do
  describe "#call" do
    it "returns the Facebook publisher class" do
      service = described_class.new(provider: "facebook")

      expect(service.call).to eq(true)
      expect(service.publisher_class).to eq(Publications::MetaGraphPublisher)
    end

    it "returns the Instagram publisher class" do
      service = described_class.new(provider: "instagram")

      expect(service.call).to eq(true)
      expect(service.publisher_class).to eq(Publications::InstagramPublisher)
    end

    it "returns the TikTok publisher class" do
      service = described_class.new(provider: "tiktok")

      expect(service.call).to eq(true)
      expect(service.publisher_class).to eq(Publications::TikTokPublisher)
    end

    it "returns the YouTube publisher class" do
      service = described_class.new(provider: "youtube")

      expect(service.call).to eq(true)
      expect(service.publisher_class).to eq(Publications::YoutubePublisher)
    end

    it "returns failure for an unsupported provider" do
      service = described_class.new(provider: "unsupported")

      expect(service.call).to eq(false)
      expect(service.publisher_class).to eq(nil)
    end
  end
end
