require "rails_helper"

RSpec.describe AiProviderConnections::CreateService, type: :service do
  let(:callback_uri) { "http://127.0.0.1:3000/ai/auth/callback" }
  let(:gemini_callback_uri) { "http://localhost:3000/ai/auth/callback" }
  let(:codex_callback_uri) { "http://localhost:1455/auth/callback" }
  let(:configuration) do
    {
      oauth_state_ttl_seconds: 600,
      host_id: "urn:uuid:4b3aa7e5-d915-43e1-b773-5219e17a880b",
      providers: {
        openai: {
          enabled: true,
          authorization_endpoint: "https://auth.openai.com/api/accounts/authorize",
          client_id: "dynamic_agent_client",
          agent_name_hint: "AffiHub",
          redirect_uri: callback_uri,
          allowed_redirect_uris: [ callback_uri ],
          resource: "https://api.openai.com/v1",
          scopes: %w[openid profile email offline_access resource.invoke chatgpt.tokens.use.direct],
          pkce_enabled: true
        },
        gemini: {
          enabled: true,
          authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
          client_id: "gemini-web-client",
          client_secret: "gemini-client-secret",
          project_id: "affihub-mvp",
          redirect_uri: gemini_callback_uri,
          allowed_redirect_uris: [ gemini_callback_uri ],
          scopes: %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever],
          pkce_enabled: true
        },
        codex: {
          enabled: true,
          authorization_endpoint: "https://auth.openai.com/oauth/authorize",
          client_id: "codex-cli-client",
          redirect_uri: codex_callback_uri,
          allowed_redirect_uris: [ codex_callback_uri ],
          scopes: %w[openid profile email offline_access],
          extra_params: {
            codex_cli_simplified_flow: "true"
          },
          pkce_enabled: true,
          nonce_enabled: false
        },
        antigravity: { enabled: false }
      }
    }
  end

  before do
    allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
  end

  describe "#call" do
    it "starts the official OpenAI dynamic registration flow" do
      service = described_class.new(provider: "openai", session: {})

      expect(service.call).to be(true)

      authorization_uri = URI(service.authorization_url)
      authorization_params = Rack::Utils.parse_query(authorization_uri.query)

      expect(authorization_uri).to have_attributes(
        scheme: "https",
        host: "auth.openai.com",
        path: "/api/accounts/authorize"
      )
      expect(authorization_params).to include(
        "client_id" => "dynamic_agent_client",
        "agent_name_hint" => "AffiHub",
        "ext_agent_host_id" => configuration.fetch(:host_id),
        "response_type" => "code",
        "redirect_uri" => callback_uri,
        "resource" => "https://api.openai.com/v1",
        "scope" => "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
        "code_challenge_method" => "S256"
      )
    end

    it "stores only a digest of state and nonce in the browser session" do
      session = {}
      service = described_class.new(provider: "openai", session:)

      service.call

      attempts = session.fetch("ai_provider_oauth_attempts")
      attempt = attempts.fetch(Digest::SHA256.hexdigest(service.state))
      authorization_params = Rack::Utils.parse_query(URI(service.authorization_url).query)
      nonce = authorization_params.fetch("nonce")

      expect(attempt).to include(
        "provider" => "openai",
        "redirect_uri" => callback_uri,
        "state_digest" => Digest::SHA256.hexdigest(service.state),
        "nonce_digest" => Digest::SHA256.hexdigest(nonce)
      )
      expect(attempt).not_to have_key("state")
      expect(attempt).not_to have_key("nonce")
      expect(session.to_json).not_to include(service.state, nonce)
    end

    it "uses PKCE S256 with the stored verifier" do
      session = {}
      service = described_class.new(provider: "openai", session:)

      service.call

      authorization_params = Rack::Utils.parse_query(URI(service.authorization_url).query)
      attempt = session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(service.state))

      expect(authorization_params.fetch("code_challenge")).to eq(
        Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.fetch("code_verifier")), padding: false)
      )
    end

    it "starts the Google Gemini API authorization flow with offline access" do
      service = described_class.new(provider: "gemini", session: {})

      expect(service.call).to be(true)

      authorization_uri = URI(service.authorization_url)
      authorization_params = Rack::Utils.parse_query(authorization_uri.query)

      expect(authorization_uri.host).to eq("accounts.google.com")
      expect(authorization_params).to include(
        "client_id" => "gemini-web-client",
        "redirect_uri" => gemini_callback_uri,
        "response_type" => "code",
        "access_type" => "offline",
        "code_challenge_method" => "S256"
      )
      expect(authorization_params.fetch("scope")).to include("https://www.googleapis.com/auth/generative-language.retriever")
    end

    it "starts the separate Codex PKCE flow against its fixed local callback" do
      session = {}
      service = described_class.new(
        provider: "codex",
        session:,
        request_origin: "http://localhost:1455"
      )

      expect(service.call).to be(true)

      authorization_uri = URI(service.authorization_url)
      authorization_params = Rack::Utils.parse_query(authorization_uri.query)
      attempt = session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(service.state))

      expect(authorization_uri).to have_attributes(
        scheme: "https",
        host: "auth.openai.com",
        path: "/oauth/authorize"
      )
      expect(authorization_params).to include(
        "client_id" => "codex-cli-client",
        "redirect_uri" => codex_callback_uri,
        "response_type" => "code",
        "scope" => "openid profile email offline_access",
        "code_challenge_method" => "S256",
        "codex_cli_simplified_flow" => "true"
      )
      expect(authorization_params).not_to include("resource", "nonce", "chatgpt.tokens.use.direct", "originator")
      expect(attempt).to include(
        "provider" => "codex",
        "client_id" => "codex-cli-client",
        "redirect_uri" => codex_callback_uri,
        "state_digest" => Digest::SHA256.hexdigest(service.state)
      )
      expect(attempt.fetch("code_verifier")).to be_present
      expect(authorization_params.fetch("code_challenge")).to eq(
        Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.fetch("code_verifier")), padding: false)
      )
      expect(attempt).not_to have_key("nonce_digest")
    end

    it "refuses to start an Antigravity OAuth flow" do
      service = described_class.new(provider: "antigravity", session: {})

      expect(service.call).to be(false)
      expect(service.authorization_url).to be_nil
      expect(service.errors.full_messages).to include("Antigravity chưa được phép kết nối với AffiHub.")
    end

    it "refuses to start OpenAI OAuth from a host that cannot receive its loopback callback" do
      service = described_class.new(
        provider: "openai",
        session: {},
        request_origin: "http://localhost:3000"
      )

      expect(service.call).to be(false)
      expect(service.authorization_url).to be_nil
      expect(service.errors.full_messages).to include("Mở AffiHub tại http://127.0.0.1:3000 để kết nối tài khoản này.")
    end

    it "refuses to start Codex OAuth from a different local host" do
      service = described_class.new(
        provider: "codex",
        session: {},
        request_origin: "http://127.0.0.1:1455"
      )

      expect(service.call).to be(false)
      expect(service.authorization_url).to be_nil
      expect(service.errors.full_messages).to include("Mở AffiHub tại http://localhost:1455 để kết nối tài khoản này.")
    end

    it "refuses to start Codex OAuth when its client ID is not configured" do
      configuration.fetch(:providers).fetch(:codex)[:client_id] = ""
      service = described_class.new(provider: "codex", session: {}, request_origin: "http://localhost:1455")

      expect(service.call).to be(false)
      expect(service.authorization_url).to be_nil
      expect(service.errors.full_messages).to include("Chưa cấu hình OAuth client ID cho Codex.")
    end
  end
end
