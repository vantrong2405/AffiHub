require "rails_helper"

RSpec.describe "ConnectionCallbacks::ShowService", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    it "returns failure for a callback from another session" do
      session = {}
      start = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      start.call
      service = "ConnectionCallbacks::ShowService".constantize.new(
        provider: "facebook", params: { state: start.state, code: "oauth-code" }, session: {},
        callback_url: "http://localhost:3000/auth/facebook/callback"
      )

      service.call

      expect(service).not_to be_success
      expect("SocialConnection".constantize.count).to eq(0)
    end

    it "returns a connection with encrypted credentials and consumes state once" do
      session = {}
      start = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      start.call
      stub_request(:get, %r{graph.facebook.com/v26.0/oauth/access_token})
        .to_return(body: { access_token: "facebook-user-secret", expires_in: 5_184_000 }.to_json)
      stub_request(:get, %r{graph.facebook.com/v26.0/me})
        .to_return(body: { id: "facebook-user-1", name: "Page Owner" }.to_json)
      callback_params = { state: start.state, code: "oauth-code" }
      callback_options = { provider: "facebook", params: callback_params, session:, callback_url: "http://localhost:3000/auth/facebook/callback" }
      service = "ConnectionCallbacks::ShowService".constantize.new(**callback_options)
      original_logger = Rails.logger
      log_output = StringIO.new

      begin
        Rails.logger = ActiveSupport::Logger.new(log_output)
        service.call

        connection = "SocialConnection".constantize.last
        expect(connection.access_token).to eq("facebook-user-secret")
        expect(connection.read_attribute_before_type_cast(:access_token)).not_to include("facebook-user-secret")
        expect(log_output.string).not_to include("facebook-user-secret")
        replay = "ConnectionCallbacks::ShowService".constantize.new(**callback_options)
        replay.call
        expect(replay).not_to be_success
      ensure
        Rails.logger = original_logger
      end
    end

    it "returns failure for an expired state without exchanging the code" do
      session = {}
      start = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      start.call
      service = "ConnectionCallbacks::ShowService".constantize.new(
        provider: "facebook", params: { state: start.state, code: "oauth-code" }, session:,
        callback_url: "http://localhost:3000/auth/facebook/callback"
      )
      travel_to(1.hour.from_now) { service.call }

      expect(service).not_to be_success
      expect("SocialConnection".constantize.count).to eq(0)
    end

    it "returns failure for a callback URL outside the configured allowlist" do
      session = {}
      start = "SocialConnections::CreateService".constantize.new(provider: "facebook", session:)
      start.call
      service = "ConnectionCallbacks::ShowService".constantize.new(
        provider: "facebook", params: { state: start.state, code: "oauth-code" }, session:,
        callback_url: "https://attacker.example/auth/facebook/callback"
      )

      service.call

      expect(service).not_to be_success
      expect("SocialConnection".constantize.count).to eq(0)
    end
  end
end
