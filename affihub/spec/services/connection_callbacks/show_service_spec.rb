require "rails_helper"

RSpec.describe "ConnectionCallbacks::ShowService", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    let(:session) { {} }
    let(:oauth_request) { SocialConnections::CreateService.new(provider: "facebook", session:) }
    let(:callback_params) { { state: oauth_request.state, code: "oauth-code" } }
    let(:callback_url) { "http://localhost:3000/auth/facebook/callback" }
    let(:callback_options) do
      { provider: "facebook", params: callback_params, session:, callback_url: }
    end
    let(:service) { ConnectionCallbacks::ShowService.new(**callback_options) }

    before do
      oauth_request.call
    end

    it "returns failure for a callback from another session" do
      callback_service = ConnectionCallbacks::ShowService.new(**callback_options.merge(session: {}))

      callback_service.call

      expect(callback_service).not_to be_success
      expect(SocialConnection.count).to eq(0)
    end

    context "when Meta accepts the callback" do
      let(:log_output) { StringIO.new }
      let!(:original_logger) { Rails.logger }

      before do
        stub_request(:get, %r{graph.facebook.com/v26.0/oauth/access_token})
          .to_return(body: { access_token: "facebook-user-secret", expires_in: 5_184_000 }.to_json)
        stub_request(:get, %r{graph.facebook.com/v26.0/me})
          .to_return(body: { id: "facebook-user-1", name: "Page Owner" }.to_json)
        Rails.logger = ActiveSupport::Logger.new(log_output)
      end

      after do
        Rails.logger = original_logger
      end

      it "returns an encrypted connection and consumes the OAuth state once" do
        service.call
        connection = SocialConnection.last
        replay_service = ConnectionCallbacks::ShowService.new(**callback_options)
        replay_service.call

        expect(connection.access_token).to eq("facebook-user-secret")
        expect(connection.read_attribute_before_type_cast(:access_token)).not_to include("facebook-user-secret")
        expect(log_output.string).not_to include("facebook-user-secret")
        expect(replay_service).not_to be_success
      end
    end

    it "returns failure for an expired state without exchanging the code" do
      travel_to(1.hour.from_now) { service.call }

      expect(service).not_to be_success
      expect(SocialConnection.count).to eq(0)
    end

    it "returns failure for a callback URL outside the configured allowlist" do
      callback_service = ConnectionCallbacks::ShowService.new(
        provider: "facebook", params: callback_params, session:,
        callback_url: "https://attacker.example/auth/facebook/callback"
      )

      callback_service.call

      expect(callback_service).not_to be_success
      expect(SocialConnection.count).to eq(0)
    end
  end
end
