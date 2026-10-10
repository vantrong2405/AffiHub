require "rails_helper"

RSpec.describe MetaCommentWebhooks::VerifyService, type: :service do
  let(:credentials) { double("credentials") }

  before do
    allow(Rails.application).to receive(:credentials).and_return(credentials)
    allow(credentials).to receive(:dig).with(:meta, :webhook_verify_token).and_return("meta-verify-token")
  end

  describe "#call" do
    it "returns success and the challenge for a valid subscribe handshake" do
      service = described_class.new(
        mode: "subscribe",
        verify_token: "meta-verify-token",
        challenge: "challenge-123"
      )

      expect(service.call).to eq(true)
      expect(service.challenge).to eq("challenge-123")
    end

    it "rejects a handshake with a different verify token" do
      service = described_class.new(
        mode: "subscribe",
        verify_token: "incorrect-token",
        challenge: "challenge-123"
      )

      expect(service.call).to eq(false)
    end

    it "rejects a handshake that requests a mode other than subscribe" do
      service = described_class.new(
        mode: "unsubscribe",
        verify_token: "meta-verify-token",
        challenge: "challenge-123"
      )

      expect(service.call).to eq(false)
    end

    it "rejects a handshake without a challenge" do
      service = described_class.new(
        mode: "subscribe",
        verify_token: "meta-verify-token",
        challenge: ""
      )

      expect(service.call).to eq(false)
    end
  end
end
