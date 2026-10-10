require "rails_helper"

RSpec.describe AiProviderConnections::CreateService, type: :service do
  let(:gemini_callback_uri) { "http://localhost:3000/ai/auth/callback" }
  let(:codex_callback_uri) { "http://localhost:1455/auth/callback" }
  let(:configuration) do
    {
      oauth_state_ttl_seconds: 600,
      providers: {
        gemini: {
          enabled: true,
          display_name: "Gemini API",
          authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
          client_id: "gemini-web-client",
          client_secret: "gemini-client-secret",
          project_id: "affihub-mvp",
          redirect_uri: gemini_callback_uri,
          allowed_redirect_uris: [ gemini_callback_uri ],
          authorization_extra_parameters: {
            access_type: "offline",
            include_granted_scopes: "true",
            prompt: "consent"
          },
          configuration_requirements: {
            shared: [],
            provider: [ :client_id, :client_secret, :project_id ],
            missing_message: "Missing provider configuration"
          },
          scopes: %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever],
          pkce_enabled: true,
          nonce_enabled: true
        },
        codex: {
          enabled: true,
          display_name: "Codex",
          authorization_endpoint: "https://auth.openai.com/oauth/authorize",
          client_id: "codex-cli-client",
          redirect_uri: codex_callback_uri,
          allowed_redirect_uris: [ codex_callback_uri ],
          authorization_extra_parameters: {
            codex_cli_simplified_flow: "true"
          },
          configuration_requirements: {
            shared: [],
            provider: [ :client_id ],
            missing_message: "Chưa cấu hình OAuth client ID cho Codex."
          },
          scopes: %w[openid profile email offline_access],
          pkce_enabled: true,
          nonce_enabled: false
        },
        antigravity: {
          enabled: false,
          display_name: "Antigravity",
          validation_messages: { disabled: "Antigravity chưa được phép kết nối với AffiHub." }
        }
      }
    }
  end

  before do
    allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
  end

  describe "#call" do
    it "rejects the removed OpenAI provider before creating an OAuth attempt" do
      allow(Rails.application).to receive(:config_for).with(:ai_providers).and_call_original
      session = {}
      service = described_class.new(provider: "openai", session:)

      expect(service.call).to eq(false)
      expect(service.authorization_url).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp AI này chưa được hỗ trợ." ])
      expect(session).to eq({})
    end

    it "rejects the legacy ChatGPT provider before creating an OAuth attempt" do
      allow(Rails.application).to receive(:config_for).with(:ai_providers).and_call_original
      session = {}
      service = described_class.new(provider: "chatgpt", session:)

      expect(service.call).to eq(false)
      expect(service.authorization_url).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp AI này chưa được hỗ trợ." ])
      expect(session).to eq({})
    end

    it "starts the Google Gemini API authorization flow with offline access" do
      configuration.fetch(:providers).fetch(:gemini)[:authorization_extra_parameters] = {
        access_type: "online",
        prompt: "select_account"
      }
      service = described_class.new(provider: "gemini", session: {})

      expect(service.call).to eq(true)

      authorization_uri = URI(service.authorization_url)
      authorization_params = Rack::Utils.parse_query(authorization_uri.query)

      expect(authorization_uri.host).to eq("accounts.google.com")
      expect(authorization_params.slice(
        "client_id", "redirect_uri", "response_type", "access_type", "prompt", "code_challenge_method"
      )).to eq(
        "client_id" => "gemini-web-client",
        "redirect_uri" => gemini_callback_uri,
        "response_type" => "code",
        "access_type" => "online",
        "prompt" => "select_account",
        "code_challenge_method" => "S256"
      )
      expect(authorization_params.fetch("scope").split).to eq(
        %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever]
      )
    end

    it "starts the separate Codex PKCE flow against its fixed local callback" do
      session = {}
      service = described_class.new(
        provider: "codex",
        session:,
        request_origin: "http://localhost:1455"
      )

      expect(service.call).to eq(true)

      authorization_uri = URI(service.authorization_url)
      authorization_params = Rack::Utils.parse_query(authorization_uri.query)
      attempt = session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(service.state))

      expect(authorization_uri).to have_attributes(
        scheme: "https",
        host: "auth.openai.com",
        path: "/oauth/authorize"
      )
      expect(authorization_params.slice(
        "client_id", "redirect_uri", "response_type", "scope", "code_challenge_method", "codex_cli_simplified_flow"
      )).to eq(
        "client_id" => "codex-cli-client",
        "redirect_uri" => codex_callback_uri,
        "response_type" => "code",
        "scope" => "openid profile email offline_access",
        "code_challenge_method" => "S256",
        "codex_cli_simplified_flow" => "true"
      )
      expect(authorization_params.keys & %w[resource nonce originator]).to eq([])
      expect(attempt.slice("provider", "client_id", "redirect_uri", "state_digest")).to eq(
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
      configuration.fetch(:providers).fetch(:antigravity).fetch(:validation_messages)[:disabled] = "Wrong YAML message"
      service = described_class.new(provider: "antigravity", session: {})

      expect(service.call).to eq(false)
      expect(service.authorization_url).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Antigravity chưa được phép kết nối với AffiHub." ])
    end

    it "refuses to start Codex OAuth from a different local host" do
      service = described_class.new(
        provider: "codex",
        session: {},
        request_origin: "http://127.0.0.1:1455"
      )

      expect(service.call).to eq(false)
      expect(service.authorization_url).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Mở AffiHub tại http://localhost:1455 để kết nối tài khoản này." ])
    end

    it "refuses to start Codex OAuth when its client ID is not configured" do
      configuration.fetch(:providers).fetch(:codex)[:client_id] = ""
      configuration.fetch(:providers).fetch(:codex).fetch(:configuration_requirements)[:missing_message] = "Wrong YAML message"
      service = described_class.new(provider: "codex", session: {}, request_origin: "http://localhost:1455")

      expect(service.call).to eq(false)
      expect(service.authorization_url).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Chưa cấu hình OAuth client ID cho Codex." ])
    end
  end
end
