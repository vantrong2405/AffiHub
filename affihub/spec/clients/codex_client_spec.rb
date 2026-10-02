# frozen_string_literal: true

require "rails_helper"

RSpec.describe CodexClient do
  subject(:client) { described_class.new }

  describe "#build_authorize_url" do
    it "returns an auth.openai.com authorize URL with PKCE and the fixed callback redirect_uri" do
      url = client.build_authorize_url(state: "abc123", code_challenge: "challenge-value")
      uri = URI.parse(url)
      params = URI.decode_www_form(uri.query).to_h

      expect(uri.host).to eq("auth.openai.com")
      expect(uri.path).to eq("/oauth/authorize")
      expect(params["client_id"]).to eq(CodexClient::CONFIG.client_id)
      expect(params["redirect_uri"]).to eq("http://localhost:1455/auth/callback")
      expect(params["scope"]).to eq("openid profile email offline_access")
      expect(params["response_type"]).to eq("code")
      expect(params["code_challenge_method"]).to eq("S256")
      expect(params["code_challenge"]).to eq("challenge-value")
      expect(params["state"]).to eq("abc123")
    end
  end

  describe "#exchange_token" do
    it "POSTs the authorization code to auth.openai.com/oauth/token and returns the parsed tokens" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .with(
          headers: { "Content-Type" => "application/x-www-form-urlencoded" },
          body: {
            "grant_type" => "authorization_code",
            "code" => "auth-code",
            "code_verifier" => "verifier",
            "redirect_uri" => "http://localhost:1455/auth/callback",
            "client_id" => CodexClient::CONFIG.client_id
          }
        )
        .to_return(
          status: 200,
          body: {
            access_token: "access-token-value",
            refresh_token: "refresh-token-value",
            id_token: "id-token-value",
            expires_in: 3600
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.exchange_token(code: "auth-code", code_verifier: "verifier")

      expect(result).to eq(
        "access_token" => "access-token-value",
        "refresh_token" => "refresh-token-value",
        "id_token" => "id-token-value",
        "expires_in" => 3600
      )
    end

    it "uses the configured HTTP timeouts for the token request" do
      expect(Net::HTTP).to receive(:start).with(
        "auth.openai.com",
        443,
        use_ssl: true,
        open_timeout: CodexClient::CONFIG.open_timeout,
        read_timeout: CodexClient::CONFIG.read_timeout,
        write_timeout: CodexClient::CONFIG.write_timeout
      ).and_call_original

      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 200, body: { access_token: "a", refresh_token: "r", id_token: "i", expires_in: 3600 }.to_json)

      client.exchange_token(code: "auth-code", code_verifier: "verifier")
    end

    it "raises Codex::TokenExchangeError when auth.openai.com returns an error" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 400, body: { error: "invalid_grant" }.to_json)

      expect do
        client.exchange_token(code: "bad-code", code_verifier: "verifier")
      end.to raise_error(CodexClient::TokenExchangeError)
    end

    it "rejects a successful token response missing required credentials" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 200, body: { access_token: "access-token", expires_in: 3600 }.to_json)

      expect { client.exchange_token(code: "auth-code", code_verifier: "verifier") }
        .to raise_error(CodexClient::TokenExchangeError)
    end
  end

  describe "#refresh_token" do
    it "POSTs the refresh_token grant and returns new access_token/refresh_token/expires_in" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .with(body: hash_including("grant_type" => "refresh_token", "refresh_token" => "old-refresh-token"))
        .to_return(
          status: 200,
          body: {
            access_token: "new-access-token",
            refresh_token: "new-refresh-token",
            expires_in: 3600
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = client.refresh_token(refresh_token: "old-refresh-token")

      expect(result).to eq(
        "access_token" => "new-access-token",
        "refresh_token" => "new-refresh-token",
        "expires_in" => 3600
      )
    end

    it "raises Codex::TokenExchangeError when the refresh_token has already been rotated/revoked" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 400, body: { error: "invalid_grant" }.to_json)

      expect do
        client.refresh_token(refresh_token: "already-used-token")
      end.to raise_error(CodexClient::TokenExchangeError)
    end

    it "rejects a successful refresh response missing a rotated refresh token" do
      stub_request(:post, "https://auth.openai.com/oauth/token")
        .to_return(status: 200, body: { access_token: "new-access-token", expires_in: 3600 }.to_json)

      expect { client.refresh_token(refresh_token: "old-refresh-token") }
        .to raise_error(CodexClient::TokenExchangeError)
    end
  end

  describe "#send_prompt" do
    it "returns the parsed response after sending Codex CLI impersonation headers to chatgpt.com/backend-api/codex/responses" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .with(
          headers: {
            "Originator" => "codex_cli_rs",
            "Authorization" => "Bearer access-token-value",
            "Chatgpt-Account-Id" => "acct-1",
            "Content-Type" => "application/json",
            "Accept" => "text/event-stream",
            "User-Agent" => "codex_cli_rs/#{CodexClient::CONFIG.cli_version}",
            "Version" => CodexClient::CONFIG.cli_version
          },
          body: {
            model: "gpt-6-luna",
            input: [ { role: "user", content: [ { type: "input_text", text: "ping" } ] } ],
            stream: true,
            store: false
          }.to_json
        )
        .to_return(
          status: 200,
          body: "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"hello from codex\"}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\"}\n\n",
          headers: { "Content-Type" => "text/event-stream" }
        )

      result = client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")

      expect(result).to eq("output_text" => "hello from codex")
    end

    it "uses the configured HTTP timeouts for the prompt request" do
      expect(Net::HTTP).to receive(:start).with(
        "chatgpt.com",
        443,
        use_ssl: true,
        open_timeout: CodexClient::CONFIG.open_timeout,
        read_timeout: CodexClient::CONFIG.read_timeout,
        write_timeout: CodexClient::CONFIG.write_timeout
      ).and_call_original

      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(status: 200, body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"ok\"}\n\ndata: {\"type\":\"response.completed\"}\n\n")

      client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
    end

    it "raises Codex::PromptRequestError when chatgpt.com returns an error" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(status: 500, body: "internal error")

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::PromptRequestError)
    end

    it "raises CodexClient::PromptRequestError when a completed stream has no output text" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(status: 200, body: "data: {\"type\":\"response.completed\"}\n\n")

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::PromptRequestError)
    end

    it "raises CodexClient::PromptRequestError when the stream contains a provider error event" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(status: 200, body: "data: {\"type\":\"error\",\"error\":{\"message\":\"failed\"}}\n\n")

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::PromptRequestError)
    end

    it "raises CodexClient::PromptRequestError when the stream ends without a completion event" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_return(status: 200, body: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n")

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::PromptRequestError)
    end

    it "raises CodexClient::TransportError when the stream request times out" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses").to_timeout

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::TransportError)
    end

    it "raises CodexClient::TransportError when the connection is refused" do
      stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
        .to_raise(Errno::ECONNREFUSED)

      expect do
        client.send_prompt(access_token: "access-token-value", chatgpt_account_id: "acct-1", prompt: "ping")
      end.to raise_error(CodexClient::TransportError)
    end
  end
end
