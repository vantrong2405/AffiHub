require "rails_helper"

RSpec.describe SocialConnections::CreateService, type: :service do
  describe "#call" do
    it "returns a Facebook authorization URL" do
      service = described_class.new(provider: "facebook", session: {})

      expect(service.call).to eq(true)
      expect(URI(service.authorization_url).host).to eq("www.facebook.com")
    end

    context "when starting TikTok OAuth" do
      let(:tiktok_configuration) { SocialConnections::ProviderConfiguration.for(:tiktok) }
      let(:callback_uri) { tiktok_configuration.fetch(:redirect_uri) }

      it "returns the TikTok authorization URL" do
        service = described_class.new(provider: "tiktok", session: {})

        expect(service.call).to eq(true)

        authorization_uri = URI(service.authorization_url)
        authorization_params = Rack::Utils.parse_query(authorization_uri.query)

        expect(authorization_uri.host).to eq("www.tiktok.com")
        expect(authorization_uri.path).to eq("/v2/auth/authorize/")
        expect(authorization_params.slice("client_key", "response_type", "redirect_uri", "scope")).to eq(
          "client_key" => "tiktok-test-client",
          "response_type" => "code",
          "redirect_uri" => callback_uri,
          "scope" => tiktok_configuration.fetch(:scopes).join(",")
        )
        expect(authorization_params).not_to have_key("client_id")
      end

      it "uses PKCE S256 for TikTok OAuth" do
        session = {}
        service = described_class.new(provider: "tiktok", session:)

        service.call

        authorization_params = Rack::Utils.parse_query(URI(service.authorization_url).query)
        state_digest = Digest::SHA256.hexdigest(service.state)
        stored_attempt = session.fetch("social_oauth_attempts").fetch(state_digest)

        expect(authorization_params.fetch("code_challenge_method")).to eq("S256")
        expect(authorization_params.fetch("code_challenge")).to eq(
          Base64.urlsafe_encode64(Digest::SHA256.digest(stored_attempt.fetch("code_verifier")), padding: false)
        )
      end

      it "stores only a digest of the TikTok OAuth state in the session" do
        session = {}
        service = described_class.new(provider: "tiktok", session:)

        service.call

        state_digest = Digest::SHA256.hexdigest(service.state)
        stored_attempt = session.fetch("social_oauth_attempts").fetch(state_digest)

        expect(stored_attempt.fetch("provider")).to eq("tiktok")
        expect(stored_attempt).not_to have_key("state")
        expect(session.to_json).not_to match(Regexp.escape(service.state))
      end

      it "generates TikTok OAuth state with 32 bytes of SecureRandom" do
        allow(SecureRandom).to receive(:urlsafe_base64).and_call_original
        expect(SecureRandom).to receive(:urlsafe_base64).with(32).and_call_original
        service = described_class.new(provider: "tiktok", session: {})

        service.call

        expect(service.state).to match(/\A[A-Za-z0-9_-]{43}\z/)
      end
    end

    context "when starting Instagram OAuth" do
      it "returns a Facebook Login for Business URL with its configured login configuration" do
        service = described_class.new(provider: "instagram", session: {})

        expect(service.call).to eq(true)

        authorization_uri = URI(service.authorization_url)
        authorization_params = Rack::Utils.parse_query(authorization_uri.query)

        expect(authorization_uri.host).to eq("www.facebook.com")
        expect(authorization_params.slice("client_id", "redirect_uri", "response_type", "config_id")).to eq(
          "client_id" => "affihub-instagram-test-client",
          "redirect_uri" => "http://localhost:3000/auth/instagram/callback",
          "response_type" => "code",
          "config_id" => "affihub-instagram-test-login-config"
        )
        expect(authorization_params).not_to have_key("scope")
      end

      it "returns a configuration error when Facebook Login for Business has no config ID" do
        configuration = SocialConnections::ProviderConfiguration.for(:instagram).deep_dup
        configuration[:authorization_params] = { config_id: "" }
        configuration[:required_authorization_parameters] = [ :config_id ]
        allow(SocialConnections::ProviderConfiguration).to receive(:for).with("instagram").and_return(configuration)
        service = described_class.new(provider: "instagram", session: {})

        expect(service.call).to eq(false)
        expect(service.errors.full_messages.to_sentence).to eq("Chưa cấu hình đầy đủ quyền kết nối cho nền tảng này.")
      end
    end

    context "when starting YouTube desktop OAuth" do
      it "returns the Google authorization URL with offline upload and channel scopes" do
        service = described_class.new(provider: "youtube", session: {})

        expect(service.call).to eq(true)

        authorization_uri = URI(service.authorization_url)
        authorization_params = Rack::Utils.parse_query(authorization_uri.query)

        expect(authorization_uri.to_s.split("?").first).to eq("https://accounts.google.com/o/oauth2/v2/auth")
        expect(authorization_params.slice("client_id", "response_type", "redirect_uri", "scope", "access_type")).to eq(
          "client_id" => "affihub-youtube-test-client",
          "response_type" => "code",
          "redirect_uri" => "http://127.0.0.1:3000/auth/youtube/callback",
          "scope" => "openid profile https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly",
          "access_type" => "offline"
        )
      end

      it "returns a PKCE S256 challenge bound to the saved one-time state" do
        session = {}
        service = described_class.new(provider: "youtube", session:)

        expect(service.call).to eq(true)

        authorization_params = Rack::Utils.parse_query(URI(service.authorization_url).query)
        attempt = session.fetch("social_oauth_attempts").fetch(Digest::SHA256.hexdigest(service.state))

        expect(authorization_params.fetch("code_challenge_method")).to eq("S256")
        expect(authorization_params.fetch("code_challenge")).to eq(
          Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.fetch("code_verifier")), padding: false)
        )
        expect(attempt.fetch("provider")).to eq("youtube")
        expect(attempt).not_to have_key("state")
      end
    end
  end
end
