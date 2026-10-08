require "rails_helper"

RSpec.describe AiProviderCallbacks::ShowService, type: :service do
  let(:openai_callback_uri) { "http://127.0.0.1:3000/ai/auth/callback" }
  let(:gemini_callback_uri) { "http://localhost:3000/ai/auth/callback" }
  let(:codex_callback_uri) { "http://localhost:1455/auth/callback" }
  let(:configuration) do
    {
      oauth_state_ttl_seconds: 600,
      statuses: {
        ai_provider_connection: {
          values: {
            pending_verification: "pending_verification",
            ready: "ready",
            scope_missing: "scope_missing",
            reauth_required: "reauth_required",
            revoked: "revoked",
            failed: "failed"
          },
          default: "pending_verification"
        }
      },
      providers: {
        openai: {
          enabled: true,
          client_id: "dynamic_agent_client",
          redirect_uri: openai_callback_uri,
          allowed_redirect_uris: [ openai_callback_uri ],
          required_scopes: [ "chatgpt.tokens.use.direct" ]
        },
        gemini: {
          enabled: true,
          client_id: "gemini-web-client",
          client_secret: "gemini-client-secret",
          project_id: "affihub-mvp",
          redirect_uri: gemini_callback_uri,
          allowed_redirect_uris: [ gemini_callback_uri ],
          required_scopes: [ "https://www.googleapis.com/auth/generative-language.retriever" ]
        },
        codex: {
          enabled: true,
          client_id: "codex-cli-client",
          openid_configuration_endpoint: "https://auth.openai.com/.well-known/openid-configuration",
          redirect_uri: codex_callback_uri,
          allowed_redirect_uris: [ codex_callback_uri ],
          scopes: %w[openid profile email offline_access],
          required_scopes: [],
          nonce_enabled: false
        },
        antigravity: {
          enabled: false
        }
      }
    }
  end
  let(:state) { "oauth-state-for-callback" }
  let(:nonce) { "oauth-nonce-for-callback" }
  let(:session) do
    {
      "ai_provider_oauth_attempts" => {
        Digest::SHA256.hexdigest(state) => {
          "provider" => "openai",
          "redirect_uri" => openai_callback_uri,
          "state_digest" => Digest::SHA256.hexdigest(state),
          "nonce_digest" => Digest::SHA256.hexdigest(nonce),
          "code_verifier" => "stored-pkce-verifier",
          "client_id" => "dynamic_agent_client",
          "expires_at" => 5.minutes.from_now.iso8601(6)
        }
      }
    }
  end
  let(:callback_params) do
    {
      "state" => state,
      "code" => "one-time-authorization-code",
      "client_id" => "oaiapp_issued-registration"
    }
  end
  let(:openai_token_response) do
    {
      "access_token" => "openai-access-secret",
      "refresh_token" => "openai-refresh-secret",
      "id_token" => "openai-id-token",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "scope" => "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    }
  end
  let(:openai_identity) do
    {
      "sub" => "openai-user-123",
      "email" => "creator@example.com",
      "name" => "AffiHub Creator",
      "nonce" => nonce
    }
  end
  let(:openai_models) do
    [
      {
        "slug" => "gpt-6-luna",
        "display_name" => "GPT 6 Luna",
        "visibility" => "list"
      }
    ]
  end
  let(:openai_client) { instance_double(OpenAi::Client) }

  before do
    allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
  end

  describe "#call for OpenAI" do
    let(:service) do
      described_class.new(
        params: callback_params,
        session:,
        callback_url: openai_callback_uri
      )
    end

    before do
      allow(OpenAi::Client).to receive(:new).and_return(openai_client)
      allow(openai_client).to receive(:exchange_code).and_return(openai_token_response)
      allow(openai_client).to receive(:verify_id_token).and_return(openai_identity)
      allow(openai_client).to receive(:list_models).and_return(openai_models)
    end

    it "exchanges the code using the issued dynamic client ID and PKCE verifier" do
      service.call

      expect(openai_client).to have_received(:exchange_code).with(
        code: "one-time-authorization-code",
        client_id: "oaiapp_issued-registration",
        code_verifier: "stored-pkce-verifier",
        redirect_uri: openai_callback_uri
      )
    end

    it "saves a verified ChatGPT connection with encrypted credentials and account models" do
      expect(service.call).to be(true)

      connection = AiProviderConnection.find_by!(provider: "openai", provider_subject: "openai-user-123")

      expect(connection).to have_attributes(
        provider_client_id: "oaiapp_issued-registration",
        account_email: "creator@example.com",
        display_name: "AffiHub Creator",
        scopes: %w[openid profile email offline_access resource.invoke chatgpt.tokens.use.direct],
        available_models: openai_models,
        status: "ready"
      )
      expect(connection.access_token).to eq("openai-access-secret")
      expect(connection.refresh_token).to eq("openai-refresh-secret")
      expect(connection.read_attribute_before_type_cast(:access_token)).not_to include("openai-access-secret")
      expect(connection.read_attribute_before_type_cast(:refresh_token)).not_to include("openai-refresh-secret")
      expect(session.fetch("ai_provider_oauth_attempts")).to be_empty
    end

    it "checks the returned ID token nonce against the saved OAuth attempt" do
      allow(openai_client).to receive(:verify_id_token).and_return(openai_identity.merge("nonce" => "wrong-nonce"))

      expect(service.call).to be(false)
      expect(AiProviderConnection.count).to eq(0)
      expect(openai_client).not_to have_received(:list_models)
    end

    it "rejects a callback from another browser session before exchanging its code" do
      service = described_class.new(
        params: callback_params.merge("state" => "state-from-another-session"),
        session:,
        callback_url: openai_callback_uri
      )

      expect(service.call).to be(false)
      expect(openai_client).not_to have_received(:exchange_code)
      expect(AiProviderConnection.count).to eq(0)
    end

    it "rejects a callback URI outside the configured allowlist before exchanging its code" do
      service = described_class.new(
        params: callback_params,
        session:,
        callback_url: "http://evil.example/ai/auth/callback"
      )

      expect(service.call).to be(false)
      expect(openai_client).not_to have_received(:exchange_code)
    end

    it "rejects an expired OAuth attempt before exchanging its code" do
      session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(state))["expires_at"] = 1.minute.ago.iso8601(6)

      expect(service.call).to be(false)
      expect(openai_client).not_to have_received(:exchange_code)
    end

    it "rejects a replay after consuming the OAuth state once" do
      expect(service.call).to be(true)

      replay_service = described_class.new(
        params: callback_params,
        session:,
        callback_url: openai_callback_uri
      )

      expect(replay_service.call).to be(false)
      expect(openai_client).to have_received(:exchange_code).once
    end

    it "rejects a returned client ID that differs from the saved registration on reauthorization" do
      session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(state))["client_id"] = "oaiapp_saved-registration"

      expect(service.call).to be(false)
      expect(openai_client).not_to have_received(:exchange_code)
    end

    it "does not replace a saved account when reauthorization returns another identity" do
      saved_connection = create(
        :ai_provider_connection,
        provider_subject: "openai-user-123",
        provider_client_id: "oaiapp_saved-registration",
        access_token: "saved-openai-access-token"
      )
      attempt = session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(state))
      attempt["client_id"] = saved_connection.provider_client_id
      attempt["connection_id"] = saved_connection.id
      allow(openai_client).to receive(:verify_id_token).and_return(
        openai_identity.merge("sub" => "another-openai-user")
      )
      service = described_class.new(
        params: callback_params.merge("client_id" => saved_connection.provider_client_id),
        session:,
        callback_url: openai_callback_uri
      )

      expect(service.call).to be(false)
      expect(saved_connection.reload).to have_attributes(
        provider_subject: "openai-user-123",
        access_token: "saved-openai-access-token"
      )
      expect(AiProviderConnection.count).to eq(1)
      expect(openai_client).not_to have_received(:list_models)
    end

    it "keeps identity-only sign-in unavailable for LLM inference when the usage scope was not granted" do
      allow(openai_client).to receive(:exchange_code).and_return(
        openai_token_response.merge("scope" => "openid profile email offline_access")
      )

      expect(service.call).to be(true)

      connection = AiProviderConnection.find_by!(provider: "openai", provider_subject: "openai-user-123")

      expect(connection.status).to eq("scope_missing")
      expect(connection.available_models).to eq([])
      expect(openai_client).not_to have_received(:list_models)
    end
  end

  describe "#call for Gemini" do
    let(:gemini_nonce) { "gemini-oauth-nonce" }
    let(:gemini_state) { "gemini-oauth-state" }
    let(:gemini_session) do
      {
        "ai_provider_oauth_attempts" => {
          Digest::SHA256.hexdigest(gemini_state) => {
            "provider" => "gemini",
            "redirect_uri" => gemini_callback_uri,
            "state_digest" => Digest::SHA256.hexdigest(gemini_state),
            "nonce_digest" => Digest::SHA256.hexdigest(gemini_nonce),
            "code_verifier" => "gemini-pkce-verifier",
            "expires_at" => 5.minutes.from_now.iso8601(6)
          }
        }
      }
    end
    let(:gemini_client) { instance_double(Gemini::Client) }
    let(:gemini_token_response) do
      {
        "access_token" => "gemini-access-secret",
        "refresh_token" => "gemini-refresh-secret",
        "id_token" => "gemini-id-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "openid email profile https://www.googleapis.com/auth/generative-language.retriever"
      }
    end
    let(:gemini_identity) do
      {
        "sub" => "google-user-456",
        "email" => "creator@gmail.com",
        "name" => "AffiHub Creator",
        "nonce" => gemini_nonce
      }
    end
    let(:gemini_models) do
      [ { "slug" => "models/gemini-3.8-flash", "display_name" => "Gemini 3.8 Flash" } ]
    end
    let(:service) do
      described_class.new(
        params: { "state" => gemini_state, "code" => "google-authorization-code" },
        session: gemini_session,
        callback_url: gemini_callback_uri
      )
    end

    before do
      allow(Gemini::Client).to receive(:new).and_return(gemini_client)
      allow(gemini_client).to receive(:exchange_code).and_return(gemini_token_response)
      allow(gemini_client).to receive(:verify_id_token).and_return(gemini_identity)
      allow(gemini_client).to receive(:list_models).and_return(gemini_models)
    end

    it "stores a valid Google connection as pending verification until Gemini inference and quota are proven" do
      expect(service.call).to be(true)

      connection = AiProviderConnection.find_by!(provider: "gemini", provider_subject: "google-user-456")

      expect(connection).to have_attributes(
        account_email: "creator@gmail.com",
        scopes: %w[openid email profile https://www.googleapis.com/auth/generative-language.retriever],
        available_models: gemini_models,
        status: "pending_verification"
      )
      expect(connection.access_token).to eq("gemini-access-secret")
      expect(connection.refresh_token).to eq("gemini-refresh-secret")
    end

    it "does not list Gemini models when OAuth did not grant the required API scope" do
      allow(gemini_client).to receive(:exchange_code).and_return(
        gemini_token_response.merge("scope" => "openid email profile")
      )

      expect(service.call).to be(true)

      connection = AiProviderConnection.find_by!(provider: "gemini", provider_subject: "google-user-456")

      expect(connection).to have_attributes(
        status: "scope_missing",
        scopes: %w[openid email profile],
        available_models: []
      )
      expect(gemini_client).not_to have_received(:list_models)
    end

    it "does not persist a Gemini token when the ID token nonce is invalid" do
      allow(gemini_client).to receive(:verify_id_token).and_return(gemini_identity.merge("nonce" => "wrong-nonce"))

      expect(service.call).to be(false)
      expect(AiProviderConnection.count).to eq(0)
      expect(gemini_client).not_to have_received(:list_models)
    end

    it "rejects a Gemini callback from a different browser session before exchanging its code" do
      foreign_session_service = described_class.new(
        params: { "state" => gemini_state, "code" => "google-authorization-code" },
        session: {},
        callback_url: gemini_callback_uri
      )

      expect(foreign_session_service.call).to be(false)
      expect(gemini_client).not_to have_received(:exchange_code)
      expect(AiProviderConnection.count).to eq(0)
    end

    it "rejects a Gemini callback from a host outside its allowlist before exchanging its code" do
      foreign_host_service = described_class.new(
        params: { "state" => gemini_state, "code" => "google-authorization-code" },
        session: gemini_session,
        callback_url: openai_callback_uri
      )

      expect(foreign_host_service.call).to be(false)
      expect(gemini_client).not_to have_received(:exchange_code)
      expect(AiProviderConnection.count).to eq(0)
    end

    it "rejects a replayed Gemini callback after consuming its state once" do
      replay_service = described_class.new(
        params: { "state" => gemini_state, "code" => "google-authorization-code" },
        session: gemini_session,
        callback_url: gemini_callback_uri
      )

      expect(service.call).to be(true)
      expect(replay_service.call).to be(false)
      expect(gemini_client).to have_received(:exchange_code).once
    end

    it "does not replace the selected Google account when reauthorization returns another identity" do
      saved_connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_subject: "google-user-456",
        provider_client_id: "gemini-web-client",
        status: :pending_verification,
        available_models: gemini_models,
        selected_model: "models/gemini-3.8-flash",
        access_token: "saved-gemini-access-token"
      )
      attempt = gemini_session.fetch("ai_provider_oauth_attempts").fetch(Digest::SHA256.hexdigest(gemini_state))
      attempt["connection_id"] = saved_connection.id
      allow(gemini_client).to receive(:verify_id_token).and_return(
        gemini_identity.merge("sub" => "another-google-user")
      )
      reauthorization_service = described_class.new(
        params: { "state" => gemini_state, "code" => "google-authorization-code" },
        session: gemini_session,
        callback_url: gemini_callback_uri
      )

      expect(reauthorization_service.call).to be(false)
      expect(saved_connection.reload).to have_attributes(
        provider_subject: "google-user-456",
        access_token: "saved-gemini-access-token"
      )
      expect(AiProviderConnection.count).to eq(1)
      expect(gemini_client).not_to have_received(:list_models)
    end
  end

  describe "#call for Codex" do
    let(:codex_state) { "codex-oauth-state" }
    let(:codex_session) do
      {
        "ai_provider_oauth_attempts" => {
          Digest::SHA256.hexdigest(codex_state) => {
            "provider" => "codex",
            "redirect_uri" => codex_callback_uri,
            "state_digest" => Digest::SHA256.hexdigest(codex_state),
            "code_verifier" => "codex-pkce-verifier",
            "client_id" => "codex-cli-client",
            "expires_at" => 5.minutes.from_now.iso8601(6)
          }
        }
      }
    end
    let(:codex_token_response) do
      {
        "access_token" => "codex-access-secret",
        "refresh_token" => "codex-refresh-secret",
        "id_token" => "codex-id-token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "openid profile email offline_access"
      }
    end
    let(:codex_identity) do
      {
        "sub" => "codex-user-789",
        "email" => "creator@example.com",
        "name" => "AffiHub Creator"
      }
    end
    let(:codex_client) { instance_double(Codex::Client) }
    let(:identity_client) { instance_double(OpenAi::Client) }
    let(:service) do
      described_class.new(
        params: { "state" => codex_state, "code" => "codex-authorization-code" },
        session: codex_session,
        callback_url: codex_callback_uri
      )
    end

    before do
      allow(Codex::Client).to receive(:new).and_return(codex_client)
      allow(codex_client).to receive(:exchange_code).and_return(codex_token_response)
      allow(OpenAi::Client).to receive(:new).and_return(identity_client)
      allow(identity_client).to receive(:verify_id_token).and_return(codex_identity)
      allow(identity_client).to receive(:list_models)
    end

    it "saves a separately authenticated Codex connection as pending verification without listing models" do
      expect(service.call).to be(true)

      connection = AiProviderConnection.find_by!(provider: "codex", provider_subject: "codex-user-789")

      expect(codex_client).to have_received(:exchange_code).with(
        code: "codex-authorization-code",
        client_id: "codex-cli-client",
        code_verifier: "codex-pkce-verifier",
        redirect_uri: codex_callback_uri
      )
      expect(identity_client).to have_received(:verify_id_token).with(
        id_token: "codex-id-token",
        client_id: "codex-cli-client"
      )
      expect(connection).to have_attributes(
        provider_client_id: "codex-cli-client",
        account_email: "creator@example.com",
        display_name: "AffiHub Creator",
        scopes: %w[openid profile email offline_access],
        available_models: [],
        selected_model: nil,
        status: "pending_verification"
      )
      expect(connection.access_token).to eq("codex-access-secret")
      expect(connection.refresh_token).to eq("codex-refresh-secret")
      expect(connection.read_attribute_before_type_cast(:access_token)).not_to include("codex-access-secret")
      expect(connection.read_attribute_before_type_cast(:refresh_token)).not_to include("codex-refresh-secret")
      expect(codex_session.fetch("ai_provider_oauth_attempts")).to be_empty
      expect(identity_client).not_to have_received(:list_models)
    end

    it "rejects a replayed Codex callback before exchanging its code a second time" do
      replay_service = described_class.new(
        params: { "state" => codex_state, "code" => "codex-authorization-code" },
        session: codex_session,
        callback_url: codex_callback_uri
      )

      expect(service.call).to be(true)
      expect(replay_service.call).to be(false)
      expect(codex_client).to have_received(:exchange_code).once
      expect(AiProviderConnection.count).to eq(1)
    end

    it "rejects a Codex callback from another local host before exchanging its code" do
      service_from_another_host = described_class.new(
        params: { "state" => codex_state, "code" => "codex-authorization-code" },
        session: codex_session,
        callback_url: "http://127.0.0.1:1455/auth/callback"
      )

      expect(service_from_another_host.call).to be(false)
      expect(codex_client).not_to have_received(:exchange_code)
      expect(AiProviderConnection.count).to eq(0)
    end

    it "rejects a Codex callback that names a different OAuth client ID" do
      callback_with_another_client = described_class.new(
        params: { "state" => codex_state, "code" => "codex-authorization-code", "client_id" => "other-client" },
        session: codex_session,
        callback_url: codex_callback_uri
      )

      expect(callback_with_another_client.call).to be(false)
      expect(codex_client).not_to have_received(:exchange_code)
      expect(AiProviderConnection.count).to eq(0)
    end
  end

  describe "#call for Antigravity" do
    let(:antigravity_state) { "antigravity-oauth-state" }
    let(:antigravity_session) do
      {
        "ai_provider_oauth_attempts" => {
          Digest::SHA256.hexdigest(antigravity_state) => {
            "provider" => "antigravity",
            "state_digest" => Digest::SHA256.hexdigest(antigravity_state),
            "expires_at" => 5.minutes.from_now.iso8601(6)
          }
        }
      }
    end
    let(:service) do
      described_class.new(
        params: { "state" => antigravity_state, "code" => "antigravity-authorization-code" },
        session: antigravity_session,
        callback_url: openai_callback_uri
      )
    end

    before do
      allow(OpenAi::Client).to receive(:new)
      allow(Gemini::Client).to receive(:new)
    end

    it "rejects the disabled provider before exchanging a callback token" do
      expect(service.call).to be(false)
      expect(OpenAi::Client).not_to have_received(:new)
      expect(Gemini::Client).not_to have_received(:new)
      expect(AiProviderConnection.count).to eq(0)
    end
  end
end
