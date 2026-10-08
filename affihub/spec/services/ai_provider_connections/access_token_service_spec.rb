require "rails_helper"

RSpec.describe AiProviderConnections::AccessTokenService, type: :service do
  describe "#call" do
    it "returns an unexpired access token without calling OpenAI" do
      connection = create(:ai_provider_connection, status: :ready, access_token_expires_at: 10.minutes.from_now)
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to be(true)
      expect(service.access_token).to eq("provider-access-token")
    end

    it "refreshes an expired OpenAI token and saves rotated credentials" do
      connection = create(
        :ai_provider_connection,
        status: :ready,
        access_token_expires_at: 1.minute.ago
      )
      openai_client = instance_double(OpenAi::Client, refresh_token: {
        "access_token" => "rotated-access-token",
        "refresh_token" => "rotated-refresh-token",
        "expires_in" => 3600
      })
      allow(OpenAi::Client).to receive(:new).and_return(openai_client)
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to be(true)
      expect(service.access_token).to eq("rotated-access-token")
      expect(connection.reload).to have_attributes(
        access_token: "rotated-access-token",
        refresh_token: "rotated-refresh-token",
        status: "ready"
      )
      expect(openai_client).to have_received(:refresh_token).with(
        refresh_token: "provider-refresh-token",
        client_id: connection.provider_client_id
      )
    end

    it "marks an OpenAI connection for reauthorization when the refresh grant is invalid" do
      connection = create(:ai_provider_connection, status: :ready, access_token_expires_at: 1.minute.ago)
      openai_client = instance_double(OpenAi::Client)
      allow(OpenAi::Client).to receive(:new).and_return(openai_client)
      allow(openai_client).to receive(:refresh_token).and_raise(OpenAi::Client::Error.new("invalid_grant"))
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to be(false)
      expect(connection.reload).to be_reauth_required
      expect(service.errors.full_messages).to include("Tài khoản AI cần đăng nhập lại.")
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

      expect(service.call).to be(false)
      expect(service.errors.full_messages).to include("Gemini API đang chờ xác minh trước khi sử dụng.")
    end

    it "does not return or refresh a Codex token while Codex inference is unverified" do
      connection = create(
        :ai_provider_connection,
        provider: "codex",
        provider_client_id: "codex-cli-client",
        status: :pending_verification,
        access_token_expires_at: 1.minute.ago
      )
      allow(OpenAi::Client).to receive(:new)
      service = described_class.new(ai_provider_connection_id: connection.id)

      expect(service.call).to be(false)
      expect(service.access_token).to be_nil
      expect(service.errors.full_messages).to include("Nhà cung cấp này chưa hỗ trợ tạo nội dung.")
      expect(OpenAi::Client).not_to have_received(:new)
    end
  end
end
