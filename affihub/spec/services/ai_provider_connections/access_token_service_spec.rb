require "rails_helper"

RSpec.describe AiProviderConnections::AccessTokenService, type: :service do
  describe "#call" do
    context "when refreshing a verified Gemini connection" do
      let(:configuration) do
        {
          token_refresh_buffer_seconds: 60,
          providers: {
            gemini: {
              capabilities: {
                inference_enabled: true,
                script_generation: true,
                scene_prompt_generation: true
              },
              inference_disabled_message: "Configured inference gate message",
              required_scopes: [ "https://www.googleapis.com/auth/generative-language.retriever" ],
              clients: { token: "Gemini::Client" },
              refresh_token_arguments: []
            }
          }
        }
      end
      let(:connection) do
        create(
          :ai_provider_connection,
          provider: "gemini",
          provider_client_id: "gemini-web-client",
          status: :ready,
          scopes: %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever],
          available_models: [ { "slug" => "models/gemini-3.8-flash", "display_name" => "Gemini Flash" } ],
          selected_model: "models/gemini-3.8-flash",
          access_token_expires_at: 1.minute.ago
        )
      end
      let(:gemini_client) do
        instance_double(Gemini::Client, refresh_token: {
          "access_token" => "rotated-gemini-access-token",
          "refresh_token" => "rotated-gemini-refresh-token",
          "expires_in" => 3600,
          "scope" => "openid email profile https://www.googleapis.com/auth/generative-language.retriever"
        })
      end
      let(:service) { described_class.new(ai_provider_connection_id: connection.id) }

      before do
        allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
        allow(Gemini::Client).to receive(:new).and_return(gemini_client)
      end

      it "returns no access token when the YAML inference gate is off" do
        allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(
          configuration.deep_merge(providers: { gemini: { capabilities: { inference_enabled: false } } })
        )

        expect(service.call).to eq(false)
        expect(service.access_token).to eq(nil)
        expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
        expect(gemini_client).not_to have_received(:refresh_token)
      end

      it "returns the existing Gemini token without refreshing it before expiry" do
        connection.update!(access_token_expires_at: 10.minutes.from_now)
        expect(gemini_client).not_to receive(:refresh_token)

        expect(service.call).to eq(true)
        expect(service.access_token).to eq("provider-access-token")
      end

      it "returns the refreshed Gemini token and saves verified credentials" do
        expect(service.call).to eq(true)
        expect(service.access_token).to eq("rotated-gemini-access-token")
        expect(connection.reload).to have_attributes(
          access_token: "rotated-gemini-access-token",
          refresh_token: "rotated-gemini-refresh-token",
          status: "ready"
        )
        expect(gemini_client).to have_received(:refresh_token).with(refresh_token: "provider-refresh-token")
      end

      it "requires the account to sign in again when Google rejects its refresh token" do
        allow(gemini_client).to receive(:refresh_token).and_raise(Gemini::Client::Error.new("invalid_grant"))

        expect(service.call).to eq(false)
        expect(connection.reload.status).to eq("reauth_required")
        expect(service.access_token).to eq(nil)
        expect(service.errors.full_messages).to eq([ "Tài khoản AI cần đăng nhập lại." ])
      end

      it "blocks inference when a refresh response no longer grants the required Gemini scope" do
        allow(gemini_client).to receive(:refresh_token).and_return(
          "access_token" => "rotated-gemini-access-token",
          "expires_in" => 3600,
          "scope" => "openid email profile"
        )

        expect(service.call).to eq(false)
        expect(connection.reload).to be_scope_missing
        expect(service.access_token).to eq(nil)
        expect(service.errors.full_messages).to eq([ "Tài khoản AI không còn quyền sử dụng model." ])
      end
    end

    it "does not refresh Gemini while Gemini inference is unverified" do
      connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_client_id: "gemini-web-client",
        status: :pending_verification,
        access_token_expires_at: 1.minute.ago
      )
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to eq(false)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end

    it "does not return or refresh a Codex token while Codex inference is unverified" do
      connection = create(
        :ai_provider_connection,
        provider: "codex",
        provider_client_id: "codex-cli-client",
        status: :pending_verification,
        access_token_expires_at: 1.minute.ago
      )
      expect(Codex::Client).not_to receive(:new)
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to eq(false)
      expect(service.access_token).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end
  end
end
