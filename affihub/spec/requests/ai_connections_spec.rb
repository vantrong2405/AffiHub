# frozen_string_literal: true

require "rails_helper"
require "socket"

RSpec.describe "AiConnections", type: :request do
  let(:user) { create(:user) }

  before { post "/login", params: { email: user.email, password: "password123" } }

  describe "POST #connect" do
    it "does not expose the connect action to GET requests" do
      get connect_ai_connection_path

      expect(response).to have_http_status(:not_found)
    end

    it "redirects to the real auth.openai.com authorize URL and returns immediately without blocking" do
      post connect_ai_connection_path, params: { listener_timeout: 0.2 }

      expect(response).to redirect_to(%r{\Ahttps://auth\.openai\.com/oauth/authorize})
      sleep 0.3
    end

    it "redirects to the AI connection page with an alert instead of auth.openai.com when port 1455 is already in use" do
      blocker = TCPServer.new("127.0.0.1", 1455)

      post connect_ai_connection_path, params: { listener_timeout: 0.2 }

      expect(response).to redirect_to(ai_connection_path)
      expect(flash[:alert]).to eq("Port #{CodexClient::CONFIG.callback_port} đang bận, đóng ứng dụng khác đang dùng port này")
    ensure
      blocker&.close
    end
  end

  describe "GET #callback_result" do
    it "sets a success notice and redirects to the AI connection page when outcome=success" do
      get callback_result_ai_connection_path, params: { outcome: "success" }

      expect(response).to redirect_to(ai_connection_path)
      expect(flash[:notice]).to eq("Codex connected successfully")
    end

    it "sets an alert with the failure reason and redirects to the AI connection page when outcome=error" do
      get callback_result_ai_connection_path, params: { outcome: "error", reason: "state_mismatch" }

      expect(response).to redirect_to(ai_connection_path)
      expect(flash[:alert]).to eq("Codex connection failed (state_mismatch)")
    end
  end

  describe "POST #test_connection" do
    it "renders the AI connection page with the real Codex response in the notice on success" do
      create(:ai_connection, user: user, access_token_expires_at: 1.hour.from_now)
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(
          status: 200,
          body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"pong\"}\n\ndata: {\"type\":\"response.completed\"}\n\n",
          headers: { "Content-Type" => "text/event-stream" }
        )

      post test_connection_ai_connection_path

      expect(response).to redirect_to(ai_connection_path)
      expect(flash[:notice]).to include("pong")
    end

    it "returns 422 with a clear alert when there is no connected AIConnection" do
      post test_connection_ai_connection_path

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash.now[:alert]).to eq("AI connection đã mất kết nối, cần kết nối lại")
    end
  end
end
