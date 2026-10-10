require "rails_helper"

RSpec.describe "GoogleConnections::CreateService", type: :service do
  describe "#call" do
    let(:session) { {} }
    let(:service_class) { GoogleConnections::CreateService }

    context "when starting a Drive connection" do
      let(:service) { service_class.new(integration: "drive", session:) }

      it "returns an authorization URL with the minimum Drive scope and offline access" do
        expect(service.call).to eq(true)

        parameters = Rack::Utils.parse_query(URI(service.authorization_url).query)

        expect(parameters.slice("scope", "access_type")).to eq(
          "scope" => "openid email https://www.googleapis.com/auth/drive.file",
          "access_type" => "offline"
        )
      end

      it "returns a PKCE S256 challenge bound to a one-time state" do
        expect(service.call).to eq(true)

        parameters = Rack::Utils.parse_query(URI(service.authorization_url).query)
        attempt = session.fetch("google_oauth_attempts").fetch(Digest::SHA256.hexdigest(service.state))

        expect(parameters.fetch("code_challenge_method")).to eq("S256")
        expect(parameters.fetch("code_challenge")).to eq(
          Base64.urlsafe_encode64(Digest::SHA256.digest(attempt.fetch("code_verifier")), padding: false)
        )
        expect(attempt.slice("integration", "redirect_uri")).to eq(
          "integration" => "drive",
          "redirect_uri" => "http://127.0.0.1:3000/auth/google/callback"
        )
      end

      it "stores only the digest of the random state in the browser session" do
        allow(SecureRandom).to receive(:urlsafe_base64).and_call_original
        expect(SecureRandom).to receive(:urlsafe_base64).with(32).and_call_original

        service.call

        state_digest = Digest::SHA256.hexdigest(service.state)
        attempts = session.fetch("google_oauth_attempts")

        expect(attempts.keys).to eq([ state_digest ])
        expect(attempts.fetch(state_digest).key?("state")).to eq(false)
        expect(session.to_json).not_to match(Regexp.escape(service.state))
      end
    end

    context "when starting a Sheets connection" do
      let(:service) { service_class.new(integration: "sheets", session:) }

      it "returns an authorization URL with the minimum Sheets scope and offline access" do
        expect(service.call).to eq(true)

        parameters = Rack::Utils.parse_query(URI(service.authorization_url).query)

        expect(parameters.slice("scope", "access_type")).to eq(
          "scope" => "openid email https://www.googleapis.com/auth/drive.file",
          "access_type" => "offline"
        )
      end
    end
  end
end
