require "rails_helper"

RSpec.describe AiProviderConnections::DestroyService, type: :service do
  let(:ai_provider_connection) { create(:ai_provider_connection) }
  let(:openai_client) { instance_double(OpenAi::Client, revoke_token: true) }

  before do
    allow(OpenAi::Client).to receive(:new).and_return(openai_client)
  end

  describe "#call" do
    it "revokes the provider credential and removes the local connection" do
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to be(true)
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to be(false)
      expect(openai_client).to have_received(:revoke_token).with(
        refresh_token: "provider-refresh-token",
        client_id: ai_provider_connection.provider_client_id
      )
    end

    it "removes local credentials when remote token revocation is unavailable" do
      allow(openai_client).to receive(:revoke_token).and_raise(OpenAi::Client::Error.new("provider_unavailable"))
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to be(true)
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to be(false)
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
        expect(OpenAi::Client).not_to receive(:new)
        expect(Gemini::Client).not_to receive(:new)

        expect(service.call).to be(true)
        expect(AiProviderConnection.exists?(connection_id)).to be(false)
      end
    end
  end
end
