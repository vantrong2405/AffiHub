require "rails_helper"

RSpec.describe "AI provider connection pages", type: :request do
  describe "POST /ai_provider_connections" do
    it "redirects the browser to the official OpenAI authorization page" do
      host! "127.0.0.1:3000"
      post ai_provider_connections_path, params: { provider: "openai" }

      authorization_uri = URI(response.location)
      expect(authorization_uri).to have_attributes(
        host: "auth.openai.com",
        path: "/api/accounts/authorize"
      )
    end
  end

  describe "PATCH /ai_provider_connections/:id" do
    it "updates the selected model through the account's own catalog" do
      ai_provider_connection = create(:ai_provider_connection)

      patch ai_provider_connection_path(ai_provider_connection),
            params: { ai_provider_connection: { selected_model: "gpt-6-luna" } }

      expect(response).to redirect_to(ai_provider_connection_path(ai_provider_connection))
      expect(ai_provider_connection.reload.selected_model).to eq("gpt-6-luna")
    end

    it "preserves the saved model when the selected value is absent from the catalog" do
      ai_provider_connection = create(:ai_provider_connection)

      patch ai_provider_connection_path(ai_provider_connection),
            params: { ai_provider_connection: { selected_model: "model-from-another-account" } }

      expect(response).to redirect_to(ai_provider_connection_path(ai_provider_connection))
      expect(flash[:alert]).to eq("Model này không có trong danh sách của kết nối.")
      expect(ai_provider_connection.reload.selected_model).to eq("gpt-6-luna")
    end
  end

  describe "DELETE /ai_provider_connections/:id" do
    it "removes the local connection after the provider confirms session revocation" do
      ai_provider_connection = create(:ai_provider_connection)
      stub_request(:get, "https://auth.openai.com/.well-known/openid-configuration")
        .to_return(
          status: 200,
          body: { issuer: "https://auth.openai.com", revocation_endpoint: "https://auth.openai.com/revoke" }.to_json
        )
      revocation_request = stub_request(:post, "https://auth.openai.com/revoke")
        .to_return(status: 200, body: "")

      delete ai_provider_connection_path(ai_provider_connection)

      expect(response).to redirect_to(ai_provider_connections_path)
      expect(flash[:notice]).to eq("Đã ngắt kết nối và thu hồi phiên AI.")
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to be(false)
      expect(revocation_request).to have_been_requested.once
    end
  end

  describe "GET /ai/auth/callback" do
    it "redirects an unbound callback without exchanging a token" do
      get ai_provider_callback_path, params: { state: "state-without-session" }

      expect(response).to redirect_to(ai_provider_connections_path)
      expect(flash[:alert]).to eq("OAuth state đã hết hạn, đã dùng hoặc thuộc phiên khác.")
    end

    it "explains when Google did not grant the Gemini API scope" do
      connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_subject: "google-user-without-api-scope",
        provider_client_id: "gemini-web-client",
        scopes: %w[openid email profile],
        available_models: [],
        selected_model: nil,
        status: :scope_missing
      )
      service = instance_double(
        AiProviderCallbacks::ShowService,
        success?: true,
        errors: ActiveModel::Errors.new(connection),
        ai_provider_connection: connection
      )
      allow(service).to receive(:call).and_return(true)
      allow(AiProviderCallbacks::ShowService).to receive(:new).and_return(service)

      get ai_provider_callback_path

      expect(response).to redirect_to(ai_provider_connection_path(connection))
      expect(flash[:notice]).to eq(
        "Đã đăng nhập Google nhưng chưa cấp scope Gemini API cần thiết. Hãy cấp quyền rồi kết nối lại."
      )
    end
  end
end
