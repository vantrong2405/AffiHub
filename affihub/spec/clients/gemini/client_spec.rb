require "rails_helper"

RSpec.describe Gemini::Client, type: :service do
  let(:configuration) do
    {
      authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
      token_endpoint: "https://oauth2.googleapis.com/token",
      revocation_endpoint: "https://oauth2.googleapis.com/revoke",
      api_base_url: "https://generativelanguage.googleapis.com/v1",
      generate_content_api_base_url: "https://generativelanguage.googleapis.com/v1beta",
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
    it "returns Google credentials after exchanging the authorization code with PKCE" do
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
    it "returns the verified Google identity after delegating token checks to googleauth" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc).and_return(
        { "sub" => "google-subject", "aud" => "gemini-web-client" }
      )

      identity = client.verify_id_token("google-id-token")

      expect(identity).to eq("sub" => "google-subject", "aud" => "gemini-web-client")
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
        expect(error.message).not_to match(Regexp.escape("private Google project detail"))
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

  describe "#generate_text" do
    it "returns generated text from the project-scoped OAuth request" do
      generation_request = stub_request(
        :post,
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
      ).with(
        headers: {
          "Authorization" => "Bearer gemini-access-token",
          "x-goog-user-project" => "affihub-mvp",
          "Content-Type" => "application/json"
        },
        body: {
          "contents" => [
            {
              "role" => "user",
              "parts" => [ { "text" => "Write a short video script." } ]
            }
          ]
        }.to_json
      ).to_return(
        status: 200,
        body: {
          "candidates" => [
            {
              "content" => {
                "parts" => [ { "text" => "A concise video script." } ]
              }
            }
          ]
        }.to_json
      )

      response = client.generate_text(
        access_token: "gemini-access-token",
        model: "models/gemini-3.8-flash",
        input: "Write a short video script."
      )

      expect(response).to eq("A concise video script.")
      expect(generation_request).to have_been_requested.once
    end

    it "returns only a safe quota status when generation is rate-limited" do
      stub_request(
        :post,
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
      ).to_return(
        status: 429,
        body: { error: { message: "private quota detail" } }.to_json
      )

      expect do
        client.generate_text(
          access_token: "gemini-access-token",
          model: "models/gemini-3.8-flash",
          input: "Write a short video script."
        )
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
        expect(error.message).not_to match(Regexp.escape("private Google token detail"))
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
