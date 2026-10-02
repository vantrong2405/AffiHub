# frozen_string_literal: true

require "rails_helper"

RSpec.describe "SocialConnections", type: :request do
  let(:user) { create(:user) }
  let(:config) { Rails.application.config_for(:facebook) }

  before { post "/login", params: { email: user.email, password: "password123" } }

  describe "GET /social_connections/connect" do
    it "stores a one-time state and redirects to Meta OAuth" do
      get "/social_connections/connect"

      expect(response).to redirect_to(%r{\Ahttps://www\.facebook\.com/v25\.0/dialog/oauth})
      expect(request.session[:facebook_oauth_state]).to be_present
    end
  end

  describe "GET /social_connections/callback" do
    it "rejects a state mismatch without exchanging a code" do
      exchange = stub_request(:post, config.token_url)

      get "/social_connections/callback", params: { code: "oauth-code", state: "wrong-state" }

      expect(response).to redirect_to(social_connections_path)
      expect(flash[:alert]).to eq("Facebook OAuth state không hợp lệ. Hãy thử kết nối lại.")
      expect(exchange).not_to have_been_requested
    end

    it "consumes matching state once and persists only the long-lived token" do
      get "/social_connections/connect"
      state = request.session[:facebook_oauth_state]
      stub_request(:post, config.token_url).to_return(status: 200, body: { access_token: "short-token" }.to_json)
      stub_request(:get, /#{Regexp.escape(config.token_url)}.*/)
        .with(query: hash_including("fb_exchange_token" => "short-token"))
        .to_return(status: 200, body: { access_token: "long-token", expires_in: 5_184_000 }.to_json)

      get "/social_connections/callback", params: { code: "oauth-code", state: state }

      expect(response).to redirect_to(facebook_pages_path)
      expect(user.reload.social_connection.access_token).to eq("long-token")
      expect(request.session[:facebook_oauth_state]).to be_nil
    end

    it "reports user cancellation without creating a SocialConnection" do
      get "/social_connections/connect"
      state = request.session[:facebook_oauth_state]

      get "/social_connections/callback", params: { error: "access_denied", state: state }

      expect(response).to redirect_to(social_connections_path)
      expect(flash[:alert]).to eq("Bạn đã hủy kết nối Facebook.")
      expect(user.reload.social_connection).to be_nil
    end
  end
end
