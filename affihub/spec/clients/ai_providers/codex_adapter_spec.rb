# frozen_string_literal: true

require "rails_helper"

RSpec.describe AIProviders::CodexAdapter do
  it "returns the token refresh lead from Codex configuration" do
    expect(described_class.new.refresh_lead).to eq(CodexClient::CONFIG.refresh_lead_minutes.minutes)
  end

  describe "#exchange_token" do
    let(:signing_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:jwk) { JWT::JWK.new(signing_key, kid: "codex-test-key", use: "sig", alg: "RS256") }

    it "returns account context from a signed ID token with valid issuer audience and expiry" do
      stub_jwks
      stub_token_exchange(id_token: signed_id_token)

      tokens = described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier")

      expect(tokens["account_id"]).to eq("account-123")
      expect(tokens["plan_type"]).to eq("plus")
    end

    it "rejects an ID token with an invalid signature" do
      stub_jwks
      stub_token_exchange(id_token: signed_id_token(key: OpenSSL::PKey::RSA.generate(2048)))

      expect { described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier") }
        .to raise_error(AIProviders::Contract::ResponseError)
    end

    it "rejects an ID token from an unexpected issuer" do
      stub_jwks
      stub_token_exchange(id_token: signed_id_token(claims: valid_claims.merge("iss" => "https://attacker.example")))

      expect { described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier") }
        .to raise_error(AIProviders::Contract::ResponseError)
    end

    it "rejects an ID token with an unexpected audience" do
      stub_jwks
      stub_token_exchange(id_token: signed_id_token(claims: valid_claims.merge("aud" => "another-client")))

      expect { described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier") }
        .to raise_error(AIProviders::Contract::ResponseError)
    end

    it "rejects an expired ID token" do
      stub_jwks
      stub_token_exchange(id_token: signed_id_token(claims: valid_claims.merge("exp" => 1.minute.ago.to_i)))

      expect { described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier") }
        .to raise_error(AIProviders::Contract::ResponseError)
    end

    it "rejects a valid ID token without a Codex account ID" do
      stub_jwks
      claims = valid_claims.merge("https://api.openai.com/auth" => { "chatgpt_plan_type" => "plus" })
      stub_token_exchange(id_token: signed_id_token(claims: claims))

      expect { described_class.new.exchange_token(code: "oauth-code", code_verifier: "pkce-verifier") }
        .to raise_error(AIProviders::Contract::ResponseError)
    end

    def valid_claims
      {
        "iss" => CodexClient::CONFIG.issuer,
        "aud" => CodexClient::CONFIG.client_id,
        "exp" => 10.minutes.from_now.to_i,
        "iat" => Time.current.to_i,
        "sub" => "subject-123",
        "https://api.openai.com/auth" => {
          "chatgpt_account_id" => "account-123",
          "chatgpt_plan_type" => "plus"
        }
      }
    end

    def signed_id_token(claims: valid_claims, key: signing_key)
      JWT.encode(claims, key, "RS256", kid: "codex-test-key")
    end

    def stub_jwks
      stub_request(:get, CodexClient::CONFIG.jwks_url).to_return(
        status: 200,
        body: JWT::JWK::Set.new(jwk).export.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end

    def stub_token_exchange(id_token:)
      stub_request(:post, CodexClient::CONFIG.token_url).to_return(
        status: 200,
        body: { access_token: "access-token", refresh_token: "refresh-token", id_token:, expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end
end
