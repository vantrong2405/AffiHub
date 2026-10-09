require "rails_helper"

RSpec.describe "GoogleConnections::CallbackService", type: :service do
  describe "#call" do
    let(:state) { "google-oauth-state" }
    let(:state_digest) { Digest::SHA256.hexdigest(state) }
    let(:callback_url) { "http://127.0.0.1:3000/auth/google/callback" }
    let(:session) do
      {
        "google_oauth_attempts" => {
          state_digest => {
            "integration" => "drive",
            "redirect_uri" => callback_url,
            "expires_at" => 10.minutes.from_now.iso8601(6),
            "code_verifier" => "google-pkce-verifier"
          }
        }
      }
    end
    let(:params) { { state:, code: "google-oauth-code" } }
    let(:service_class) { GoogleConnections::CallbackService }
    let(:service) { service_class.new(params:, session:, callback_url:) }

    context "when Google accepts the callback" do
      let(:google_client) { instance_double(Google::Client) }
      let(:token_payload) do
        {
          "access_token" => "google-access-secret",
          "refresh_token" => "google-refresh-secret",
          "expires_in" => 3600,
          "scope" => "openid email https://www.googleapis.com/auth/drive.file"
        }
      end
      let(:profile) { { "sub" => "google-account-1", "email" => "creator@example.test" } }

      before do
        allow(Google::Client).to receive(:new).and_return(google_client)
        allow(google_client).to receive(:exchange_code).and_return(token_payload)
        allow(google_client).to receive(:profile).and_return(profile)
      end

      it "returns an encrypted Google connection for the selected integration" do
        expect(service.call).to eq(true)

        google_connection = GoogleConnection.find_by!(integration: "drive", google_account_id: "google-account-1")

        expect(google_connection).to have_attributes(
          email: "creator@example.test",
          access_token: "google-access-secret",
          refresh_token: "google-refresh-secret"
        )
        expect(google_connection.read_attribute_before_type_cast(:access_token)).not_to match(
          Regexp.escape("google-access-secret")
        )
        expect(google_connection.read_attribute_before_type_cast(:refresh_token)).not_to match(
          Regexp.escape("google-refresh-secret")
        )
      end

      it "consumes the one-time state before exchanging the authorization code" do
        service.call

        expect(session.fetch("google_oauth_attempts")).to eq({})
        expect(google_client).to have_received(:exchange_code).with(
          code: "google-oauth-code",
          redirect_uri: callback_url,
          code_verifier: "google-pkce-verifier"
        ).once
      end

      it "rejects replay of the consumed state without creating another connection" do
        service.call
        replay = service_class.new(params:, session:, callback_url:)

        expect(replay.call).to eq(false)
        expect(GoogleConnection.count).to eq(1)
      end
    end

    it "rejects a callback received in a different browser session" do
      callback = service_class.new(params:, session: {}, callback_url:)

      expect(callback.call).to eq(false)
      expect(GoogleConnection.count).to eq(0)
    end

    it "rejects a state that has expired" do
      expired_session = session.deep_dup
      expired_session.fetch("google_oauth_attempts").fetch(state_digest)["expires_at"] = 1.minute.ago.iso8601(6)
      callback = service_class.new(params:, session: expired_session, callback_url:)

      expect(callback.call).to eq(false)

      expect(GoogleConnection.count).to eq(0)
    end

    it "rejects a callback URL outside the configured allowlist" do
      callback = service_class.new(
        params:,
        session:,
        callback_url: "https://attacker.example/auth/google/callback"
      )

      expect(callback.call).to eq(false)
      expect(GoogleConnection.count).to eq(0)
    end
  end
end
