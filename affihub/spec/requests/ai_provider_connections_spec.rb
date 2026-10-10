require "rails_helper"

RSpec.describe "AI provider connection pages", type: :request do
  describe "GET /ai_provider_connections" do
    it "returns the provider choice page" do
      get ai_provider_connections_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /ai_provider_connections/:id" do
    it "returns the saved account detail page" do
      connection = create(:ai_provider_connection)

      get ai_provider_connection_path(connection)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /ai_provider_connections" do
    it "rejects a removed OpenAI provider before redirecting to OAuth" do
      host! "127.0.0.1:3000"
      post ai_provider_connections_path, params: { provider: "openai" }

      expect(response).to redirect_to(ai_provider_connections_path)
      expect(flash[:alert]).to eq("Nhà cung cấp AI này chưa được hỗ trợ.")
    end

    it "rejects a legacy ChatGPT provider before redirecting to OAuth" do
      post ai_provider_connections_path, params: { provider: "chatgpt" }

      expect(response).to redirect_to(ai_provider_connections_path)
      expect(flash[:alert]).to eq("Nhà cung cấp AI này chưa được hỗ trợ.")
    end
  end

  describe "PATCH /ai_provider_connections/:id" do
    it "updates the selected model through the account's own catalog" do
      ai_provider_connection = create(:ai_provider_connection)

      patch ai_provider_connection_path(ai_provider_connection),
            params: { ai_provider_connection: { selected_model: "models/gemini-3.5-flash-lite" } }

      expect(response).to redirect_to(ai_provider_connection_path(ai_provider_connection))
      expect(ai_provider_connection.reload.selected_model).to eq("models/gemini-3.5-flash-lite")
    end

    it "preserves the saved model when the selected value is absent from the catalog" do
      ai_provider_connection = create(:ai_provider_connection)

      patch ai_provider_connection_path(ai_provider_connection),
            params: { ai_provider_connection: { selected_model: "model-from-another-account" } }

      expect(response).to redirect_to(ai_provider_connection_path(ai_provider_connection))
      expect(flash[:alert]).to eq("Model này không có trong danh sách của kết nối.")
      expect(ai_provider_connection.reload.selected_model).to eq("models/gemini-3.5-flash-lite")
    end
  end

  describe "DELETE /ai_provider_connections/:id" do
    it "removes the local connection after the provider confirms session revocation" do
      ai_provider_connection = create(:ai_provider_connection)
      revocation_request = stub_request(:post, "https://oauth2.googleapis.com/revoke")
        .with(body: { "token" => "provider-refresh-token" })
        .to_return(status: 200, body: "")

      delete ai_provider_connection_path(ai_provider_connection)

      expect(response).to redirect_to(ai_provider_connections_path)
      expect(flash[:notice]).to eq("Đã ngắt kết nối và thu hồi phiên AI.")
      expect(AiProviderConnection.exists?(ai_provider_connection.id)).to eq(false)
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
      configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
      configuration.fetch(:providers).fetch(:gemini)[:display_name] = "Configured Google provider"
      allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
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
        ai_provider_connection: connection,
        provider_configuration: configuration.fetch(:providers).fetch(:gemini)
      )
      allow(service).to receive(:call).and_return(true)
      allow(AiProviderCallbacks::ShowService).to receive(:new).and_return(service)

      get ai_provider_callback_path

      expect(response).to redirect_to(ai_provider_connection_path(connection))
      expect(flash[:notice]).to eq("Đã đăng nhập Google nhưng chưa cấp quyền Configured Google provider. Hãy kết nối lại và cấp quyền.")
    end
  end
end
