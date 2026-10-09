require "rails_helper"

RSpec.describe "Instagram connection callbacks", type: :request do
  describe "GET /auth/instagram/callback" do
    it "returns a redirect to Page selection after storing the Instagram profile" do
      host! "localhost:3000"
      post social_connections_path, params: { provider: "instagram" }
      authorization_params = Rack::Utils.parse_query(URI(response.location).query)
      stub_request(:get, "https://graph.facebook.com/v26.0/oauth/access_token")
        .with(query: {
          "client_id" => "affihub-instagram-test-client",
          "client_secret" => "affihub-instagram-test-secret",
          "code" => "instagram-oauth-code",
          "redirect_uri" => "http://localhost:3000/auth/instagram/callback"
        })
        .to_return(body: { access_token: "instagram-user-token", expires_in: 5_184_000 }.to_json)
      stub_request(:get, "https://graph.facebook.com/v26.0/me")
        .with(query: { "fields" => "id,name", "access_token" => "instagram-user-token" })
        .to_return(body: { id: "instagram-user-1", name: "Bếp Nhà" }.to_json)

      get connection_callback_path(provider: "instagram"), params: {
        state: authorization_params.fetch("state"),
        code: "instagram-oauth-code"
      }

      social_connection = SocialConnection.find_by!(provider: "instagram", external_user_id: "instagram-user-1")
      expect(response).to redirect_to(social_connection_social_destinations_path(social_connection))
      expect(flash[:notice]).to eq("Tài khoản Instagram đã kết nối. Hãy chọn Page để đăng.")
    end
  end
end
