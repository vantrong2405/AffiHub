require "rails_helper"

RSpec.describe "Connection callbacks", type: :request do
  describe "GET /auth/:provider/callback" do
    it "returns a redirect without exposing the exchanged credential" do
      post social_connections_path, params: { provider: "facebook" }
      authorization_params = Rack::Utils.parse_query(URI(response.location).query)
      stub_request(:get, %r{graph.facebook.com/v26.0/oauth/access_token})
        .to_return(body: { access_token: "response-secret-token", expires_in: 5_184_000 }.to_json)
      stub_request(:get, %r{graph.facebook.com/v26.0/me})
        .to_return(body: { id: "facebook-user-1", name: "Page Owner" }.to_json)

      get connection_callback_path(provider: "facebook"), params: { state: authorization_params.fetch("state"), code: "oauth-code" }

      expect(response).to be_redirect
      expect(response.body).not_to include("response-secret-token")
      expect(response.location).not_to include("response-secret-token")
    end
  end
end
