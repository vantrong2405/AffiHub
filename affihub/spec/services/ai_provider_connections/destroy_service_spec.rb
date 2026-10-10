require "rails_helper"

RSpec.describe AiProviderConnections::DestroyService, type: :service do
  let(:ai_provider_connection) { create(:ai_provider_connection) }
  let(:gemini_client) { instance_double(Gemini::Client, revoke_token: true) }

  before do
    allow(Gemini::Client).to receive(:new).and_return(gemini_client)
  end

  describe "#call" do
    it "revokes the provider credential and removes the local connection" do
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to eq(true)
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to eq(false)
      expect(gemini_client).to have_received(:revoke_token).with(refresh_token: "provider-refresh-token")
    end

    it "removes local credentials when remote token revocation is unavailable" do
      allow(gemini_client).to receive(:revoke_token).and_raise(Gemini::Client::Error.new("provider_unavailable"))
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to eq(true)
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to eq(false)
      expect(service.errors.full_messages).to be_empty
    end

    context "when disconnecting a Codex connection" do
      let(:ai_provider_connection) do
        create(
          :ai_provider_connection,
          provider: "codex",
          provider_client_id: "codex-cli-client",
          status: :pending_verification,
          available_models: [],
          selected_model: nil
        )
      end

      it "removes local credentials without attempting unsupported remote revocation" do
        connection_id = ai_provider_connection.id
        service = described_class.new(ai_provider_connection_id: connection_id)
        expect(Codex::Client).not_to receive(:new)
        expect(Gemini::Client).not_to receive(:new)

        expect(service.call).to eq(true)
        expect(AiProviderConnection.exists?(connection_id)).to eq(false)
      end
    end

    context "when disconnecting a Gemini connection" do
      let(:ai_provider_connection) do
        create(
          :ai_provider_connection,
          provider: "gemini",
          provider_client_id: "gemini-web-client",
          status: :pending_verification,
          available_models: [],
          selected_model: nil
        )
      end
      it "revokes the Google credential and removes the local connection" do
        connection_id = ai_provider_connection.id
        service = described_class.new(ai_provider_connection_id: connection_id)

        expect(service.call).to eq(true)
        expect(AiProviderConnection.exists?(connection_id)).to eq(false)
        expect(gemini_client).to have_received(:revoke_token).with(refresh_token: "provider-refresh-token")
      end
    end
  end
end
