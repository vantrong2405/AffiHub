require "rails_helper"

RSpec.describe Codex::Client, type: :service do
  let(:configuration) do
    {
      token_endpoint: "https://auth.openai.com/oauth/token",
      connect_timeout_seconds: 5,
      read_timeout_seconds: 10
    }
  end
  let(:client) { described_class.new(configuration:) }

  describe "#exchange_code" do
    it "exchanges the authorization code with the Codex client ID and PKCE verifier" do
      token_request = stub_request(:post, "https://auth.openai.com/oauth/token")
        .with(
          headers: { "Content-Type" => "application/x-www-form-urlencoded" },
          body: {
            "grant_type" => "authorization_code",
            "client_id" => "codex-cli-client",
            "code" => "single-use-codex-code",
            "redirect_uri" => "http://localhost:1455/auth/callback",
            "code_verifier" => "codex-pkce-verifier"
          }
        )
        .to_return(status: 200, body: { access_token: "codex-access-token", id_token: "codex-id-token" }.to_json)

      response = client.exchange_code(
        code: "single-use-codex-code",
        client_id: "codex-cli-client",
        code_verifier: "codex-pkce-verifier",
        redirect_uri: "http://localhost:1455/auth/callback"
      )

      expect(response).to include("access_token" => "codex-access-token", "id_token" => "codex-id-token")
      expect(token_request).to have_been_requested.once
    end
  end

  describe "#refresh_token" do
    it "refreshes the Codex token with form-encoded OAuth credentials" do
      token_request = stub_request(:post, "https://auth.openai.com/oauth/token")
        .with(
          body: {
            "grant_type" => "refresh_token",
            "client_id" => "codex-cli-client",
            "refresh_token" => "codex-refresh-token"
          }
        )
        .to_return(status: 200, body: { access_token: "rotated-codex-token", expires_in: 3600 }.to_json)

      response = client.refresh_token(refresh_token: "codex-refresh-token", client_id: "codex-cli-client")

      expect(response).to include("access_token" => "rotated-codex-token", "expires_in" => 3600)
      expect(token_request).to have_been_requested.once
    end
  end

  describe "#exchange_code error handling" do
    it "does not expose the provider response body in token exchange errors" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 400, body: { error: { code: "invalid_grant", access_token: "provider-secret-token" } }.to_json)

      expect do
        client.exchange_code(
          code: "single-use-codex-code",
          client_id: "codex-cli-client",
          code_verifier: "codex-pkce-verifier",
          redirect_uri: "http://localhost:1455/auth/callback"
        )
      end.to raise_error(Codex::Client::Error, "invalid_grant")
    end
  end
end
