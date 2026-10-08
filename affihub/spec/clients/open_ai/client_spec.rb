require "rails_helper"

RSpec.describe OpenAi::Client, type: :service do
  let(:configuration) do
    {
      token_endpoint: "https://auth.openai.com/api/accounts/oauth/token",
      openid_configuration_endpoint: "https://auth.openai.com/.well-known/openid-configuration",
      api_base_url: "https://api.openai.com/v1",
      resource: "https://api.openai.com/v1",
      connect_timeout_seconds: 5,
      read_timeout_seconds: 10
    }
  end
  let(:client) { described_class.new(configuration:) }

  describe "#exchange_code" do
    let(:token_request) do
      stub_request(:post, "https://auth.openai.com/api/accounts/oauth/token")
        .with(
          body: {
            "grant_type" => "authorization_code",
            "code" => "single-use-code",
            "client_id" => "oaiapp-issued-client",
            "code_verifier" => "pkce-verifier",
            "redirect_uri" => "http://127.0.0.1:3000/ai/auth/callback",
            "resource" => "https://api.openai.com/v1"
          }
        )
        .to_return(
          status: 200,
          body: {
            access_token: "openai-access-token",
            refresh_token: "openai-refresh-token",
            id_token: "openai-id-token",
            expires_in: 3600
          }.to_json
        )
    end

    it "exchanges the single-use code with the issued client ID, callback URI, resource, and PKCE verifier" do
      token_request

      response = client.exchange_code(
        code: "single-use-code",
        client_id: "oaiapp-issued-client",
        code_verifier: "pkce-verifier",
        redirect_uri: "http://127.0.0.1:3000/ai/auth/callback"
      )

      expect(response.fetch("access_token")).to eq("openai-access-token")
      expect(token_request).to have_been_requested.once
    end
  end

  describe "#verify_id_token" do
    it "verifies the OpenAI signature, issuer, issued client audience, and token expiry" do
      signing_key = OpenSSL::PKey::RSA.generate(2048)
      public_jwk = JWT::JWK.new(signing_key.public_key, kid: "openai-test-key").export
      id_token = JWT.encode(
        {
          iss: "https://auth.openai.com",
          aud: "oaiapp-issued-client",
          sub: "openai-subject",
          exp: 5.minutes.from_now.to_i
        },
        signing_key,
        "RS256",
        { kid: "openai-test-key" }
      )
      stub_request(:get, "https://auth.openai.com/.well-known/openid-configuration")
        .to_return(status: 200, body: { issuer: "https://auth.openai.com", jwks_uri: "https://auth.openai.com/jwks" }.to_json)
      stub_request(:get, "https://auth.openai.com/jwks")
        .to_return(status: 200, body: { keys: [ public_jwk ] }.to_json)

      identity = client.verify_id_token(id_token:, client_id: "oaiapp-issued-client")

      expect(identity).to include("sub" => "openai-subject", "aud" => "oaiapp-issued-client")
    end
  end

  describe "#list_models" do
    it "returns only account models marked for display and keeps provider order" do
      model_request = stub_request(:get, "https://api.openai.com/v1/models")
        .with(headers: { "Authorization" => "Bearer openai-access-token" })
        .to_return(
          status: 200,
          body: {
            models: [
              { slug: "gpt-6-luna", display_name: "GPT 6 Luna", visibility: "list" },
              { slug: "internal-model", display_name: "Internal", visibility: "hidden" },
              { slug: "codex", display_name: "Codex", visibility: "list" }
            ]
          }.to_json
        )

      models = client.list_models(access_token: "openai-access-token")

      expect(models).to eq(
        [
          { "slug" => "gpt-6-luna", "display_name" => "GPT 6 Luna", "visibility" => "list" },
          { "slug" => "codex", "display_name" => "Codex", "visibility" => "list" }
        ]
      )
      expect(model_request).to have_been_requested.once
    end
  end

  describe "#refresh_token" do
    it "refreshes credentials using the issued client ID and resource" do
      refresh_request = stub_request(:post, "https://auth.openai.com/api/accounts/oauth/token")
        .with(
          body: {
            "grant_type" => "refresh_token",
            "refresh_token" => "openai-refresh-token",
            "client_id" => "oaiapp-issued-client",
            "resource" => "https://api.openai.com/v1"
          }
        )
        .to_return(status: 200, body: { access_token: "rotated-access-token", expires_in: 3600 }.to_json)

      response = client.refresh_token(refresh_token: "openai-refresh-token", client_id: "oaiapp-issued-client")

      expect(response.fetch("access_token")).to eq("rotated-access-token")
      expect(refresh_request).to have_been_requested.once
    end

    it "returns a sanitized OAuth error code when the refresh grant is invalid" do
      stub_request(:post, "https://auth.openai.com/api/accounts/oauth/token")
        .to_return(
          status: 400,
          body: { error: "invalid_grant", error_description: "private refresh token detail" }.to_json
        )

      expect do
        client.refresh_token(refresh_token: "openai-refresh-token", client_id: "oaiapp-issued-client")
      end.to raise_error(described_class::Error, "invalid_grant")
    end
  end

  describe "#revoke_token" do
    it "uses the revocation endpoint from OpenID provider metadata" do
      stub_request(:get, "https://auth.openai.com/.well-known/openid-configuration")
        .to_return(
          status: 200,
          body: { issuer: "https://auth.openai.com", revocation_endpoint: "https://auth.openai.com/revoke" }.to_json
        )
      revoke_request = stub_request(:post, "https://auth.openai.com/revoke")
        .with(
          body: {
            "token" => "openai-refresh-token",
            "token_type_hint" => "refresh_token",
            "client_id" => "oaiapp-issued-client"
          }
        )
        .to_return(status: 200, body: "")

      expect(client.revoke_token(refresh_token: "openai-refresh-token", client_id: "oaiapp-issued-client")).to be(true)
      expect(revoke_request).to have_been_requested.once
    end
  end

  describe "#generate_text" do
    it "returns output text only after a completed Responses API stream" do
      input = "Write a short Vietnamese video script."
      response_stream = [
        'event: response.output_text.delta',
        'data: {"type":"response.output_text.delta","delta":"Xin "}',
        "",
        'event: response.output_text.delta',
        'data: {"type":"response.output_text.delta","delta":"chào!"}',
        "",
        'event: response.completed',
        'data: {"type":"response.completed","response":{"status":"completed"}}',
        "",
        ""
      ].join("\n")
      response_request = stub_request(:post, "https://api.openai.com/v1/responses")
        .with(
          headers: { "Authorization" => "Bearer openai-access-token" },
          body: {
            "model" => "gpt-6-luna",
            "input" => [
              {
                "role" => "user",
                "content" => [ { "type" => "input_text", "text" => input } ]
              }
            ],
            "store" => false,
            "stream" => true
          }
        )
        .to_return(status: 200, headers: { "Content-Type" => "text/event-stream" }, body: response_stream)

      output = client.generate_text(access_token: "openai-access-token", model: "gpt-6-luna", input:)

      expect(output).to eq("Xin chào!")
      expect(response_request).to have_been_requested.once
    end

    it "rejects a Responses API stream that ends without response.completed" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n"
        )

      expect do
        client.generate_text(access_token: "openai-access-token", model: "gpt-6-luna", input: "prompt")
      end.to raise_error(described_class::Error, "response_not_completed")
    end

    it "reports a failed Responses API stream with only its safe provider error code" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: "event: response.failed\ndata: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\",\"message\":\"private provider detail\"}}}\n\n"
        )

      expect do
        client.generate_text(access_token: "openai-access-token", model: "gpt-6-luna", input: "prompt")
      end.to raise_error(described_class::Error, "subscription_sharing_usage_limit_exceeded")
    end

    it "reports a sanitized usage-limit code when the Responses API rejects the stream request" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(
          status: 429,
          body: {
            error: {
              code: "subscription_sharing_usage_limit_exceeded",
              message: "private provider detail"
            }
          }.to_json
        )

      expect do
        client.generate_text(access_token: "openai-access-token", model: "gpt-6-luna", input: "prompt")
      end.to raise_error(described_class::Error, "subscription_sharing_usage_limit_exceeded")
    end

    it "rejects an incomplete Responses API stream without returning partial text" do
      stub_request(:post, "https://api.openai.com/v1/responses")
        .to_return(
          status: 200,
          headers: { "Content-Type" => "text/event-stream" },
          body: "event: response.incomplete\ndata: {\"type\":\"response.incomplete\",\"response\":{\"status\":\"incomplete\"}}\n\n"
        )

      expect do
        client.generate_text(access_token: "openai-access-token", model: "gpt-6-luna", input: "prompt")
      end.to raise_error(described_class::Error, "response_incomplete")
    end
  end
end
