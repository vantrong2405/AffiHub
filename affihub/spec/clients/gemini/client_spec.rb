require "rails_helper"

RSpec.describe Gemini::Client, type: :service do
  let(:configuration) do
    {
      authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      token_endpoint: "https://oauth2.googleapis.com/token",
      revocation_endpoint: "https://oauth2.googleapis.com/revoke",
      api_base_url: "https://generativelanguage.googleapis.com/v1",
      client_id: "gemini-web-client",
      client_secret: "gemini-client-secret",
      project_id: "affihub-mvp",
      user_project_header: "x-goog-user-project",
      connect_timeout_seconds: 5,
      read_timeout_seconds: 10
    }
  end
  let(:client) { described_class.new(configuration:) }

  describe "#exchange_code" do
    it "exchanges a Google authorization code with the registered client and PKCE verifier" do
      token_request = stub_request(:post, "https://oauth2.googleapis.com/token")
        .with(
          body: {
            "grant_type" => "authorization_code",
            "client_id" => "gemini-web-client",
            "client_secret" => "gemini-client-secret",
            "code" => "google-single-use-code",
            "redirect_uri" => "http://localhost:3000/ai/auth/callback",
            "code_verifier" => "google-pkce-verifier"
          }
        )
        .to_return(
          status: 200,
          body: {
            access_token: "gemini-access-token",
            refresh_token: "gemini-refresh-token",
            id_token: "google-id-token",
            expires_in: 3600,
            scope: "openid https://www.googleapis.com/auth/generative-language.retriever"
          }.to_json
        )

      response = client.exchange_code(
        code: "google-single-use-code",
        code_verifier: "google-pkce-verifier",
        redirect_uri: "http://localhost:3000/ai/auth/callback"
      )

      expect(response.fetch("access_token")).to eq("gemini-access-token")
      expect(token_request).to have_been_requested.once
    end
  end

  describe "#verify_id_token" do
    it "delegates Google ID-token signature, issuer, expiry, and audience checks to googleauth" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(
        { "sub" => "google-subject", "aud" => "gemini-web-client" }
      )

      identity = client.verify_id_token("google-id-token")

      expect(identity).to include("sub" => "google-subject", "aud" => "gemini-web-client")
      expect(Google::Auth::IDTokens).to have_received(:verify_oidc).with(
        "google-id-token",
        aud: "gemini-web-client"
      )
    end
  end

  describe "#list_models" do
    it "sends the account token and Google Cloud project when listing Gemini models" do
      model_request = stub_request(:get, "https://generativelanguage.googleapis.com/v1/models")
        .with(
          headers: {
            "Authorization" => "Bearer gemini-access-token",
            "x-goog-user-project" => "affihub-mvp"
          }
        )
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "models/gemini-3.8-flash", displayName: "Gemini 3.8 Flash", supportedGenerationMethods: [ "generateContent" ] },
              { name: "models/gemini-embedding", displayName: "Gemini Embedding", supportedGenerationMethods: [ "embedContent" ] }
            ]
          }.to_json
        )

      models = client.list_models(access_token: "gemini-access-token")

      expect(models).to eq(
        [ { "slug" => "models/gemini-3.8-flash", "display_name" => "Gemini 3.8 Flash" } ]
      )
      expect(model_request).to have_been_requested.once
    end

    it "sanitizes a Gemini permission error without exposing provider response details" do
      stub_request(:get, "https://generativelanguage.googleapis.com/v1/models")
        .to_return(
          status: 403,
          body: { error: { message: "private Google project detail", status: "PERMISSION_DENIED" } }.to_json
        )

      expect do
        client.list_models(access_token: "gemini-access-token")
      end.to raise_error(described_class::Error, "http_403") { |error|
        expect(error.message).not_to include("private Google project detail")
      }
    end

    it "returns a safe quota status when Gemini rate-limits an API request" do
      stub_request(:get, "https://generativelanguage.googleapis.com/v1/models")
        .to_return(status: 429, body: { error: { message: "private quota detail" } }.to_json)

      expect do
        client.list_models(access_token: "gemini-access-token")
      end.to raise_error(described_class::Error, "http_429")
    end
  end

  describe "#refresh_token" do
    it "refreshes Google credentials with the OAuth client secret" do
      refresh_request = stub_request(:post, "https://oauth2.googleapis.com/token")
        .with(
          body: {
            "grant_type" => "refresh_token",
            "refresh_token" => "gemini-refresh-token",
            "client_id" => "gemini-web-client",
            "client_secret" => "gemini-client-secret"
          }
        )
        .to_return(status: 200, body: { access_token: "rotated-gemini-token", expires_in: 3600 }.to_json)

      response = client.refresh_token(refresh_token: "gemini-refresh-token")

      expect(response.fetch("access_token")).to eq("rotated-gemini-token")
      expect(refresh_request).to have_been_requested.once
    end

    it "exposes only the safe invalid-grant code when a refresh token is revoked" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(
          status: 400,
          body: { error: "invalid_grant", error_description: "private Google token detail" }.to_json
        )

      expect do
        client.refresh_token(refresh_token: "revoked-gemini-refresh-token")
      end.to raise_error(described_class::Error, "invalid_grant") { |error|
        expect(error.message).not_to include("private Google token detail")
      }
    end
  end

  describe "#revoke_token" do
    it "revokes the Google refresh token without sending it in the query string" do
      revoke_request = stub_request(:post, "https://oauth2.googleapis.com/revoke")
        .with(body: { "token" => "gemini-refresh-token" })
        .to_return(status: 200, body: "")

      expect(client.revoke_token(refresh_token: "gemini-refresh-token")).to be(true)
      expect(revoke_request).to have_been_requested.once
    end
  end
end
