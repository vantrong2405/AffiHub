require "rails_helper"

RSpec.describe "GoogleConnections::AccessTokenService", type: :service do
  describe "#call" do
    before { allow(Google::Client).to receive(:new).and_call_original }

    let(:google_connection) { create(:google_connection, access_token_expires_at:) }
    let(:service_class) { GoogleConnections::AccessTokenService }
    let(:service) { service_class.new(google_connection_id: google_connection.id) }
    let(:access_token_expires_at) { 1.hour.from_now }

    context "when the access token is still valid" do
      it "returns the stored access token without refreshing it" do
        expect(service.call).to eq(true)

        expect(service.access_token).to eq("google-access-token")
        expect(Google::Client).not_to have_received(:new)
      end
    end

    context "when the access token has expired" do
      let(:access_token_expires_at) { 1.minute.ago }
      let(:google_client) { instance_double(Google::Client) }

      before do
        allow(Google::Client).to receive(:new).and_return(google_client)
        allow(google_client).to receive(:refresh_access_token).with(refresh_token: "google-refresh-token").and_return(
          "access_token" => "google-refreshed-access-token",
          "expires_in" => 3600
        )
      end

      it "returns and stores the refreshed access token" do
        expect(service.call).to eq(true)

        expect(service.access_token).to eq("google-refreshed-access-token")
        expect(google_connection.reload.access_token).to eq("google-refreshed-access-token")
      end
    end

    context "when the access token expiry is unknown" do
      let(:access_token_expires_at) { nil }
      let(:google_client) { instance_double(Google::Client) }

      before do
        allow(Google::Client).to receive(:new).and_return(google_client)
        allow(google_client).to receive(:refresh_access_token).and_return(
          "access_token" => "google-refreshed-access-token",
          "expires_in" => 3600
        )
      end

      it "refreshes the token rather than assuming an unknown expiry is valid" do
        expect(service.call).to eq(true)

        expect(service.access_token).to eq("google-refreshed-access-token")
        expect(google_client).to have_received(:refresh_access_token).with(
          refresh_token: "google-refresh-token"
        ).once
      end
    end

    context "when Google rejects the refresh token" do
      let(:access_token_expires_at) { 1.minute.ago }
      let(:google_client) { instance_double(Google::Client) }

      before do
        allow(Google::Client).to receive(:new).and_return(google_client)
        allow(google_client).to receive(:refresh_access_token).and_raise(
          Google::Client::InvalidGrantError.new(status: 400, reason: "invalid_grant")
        )
      end

      it "returns a reconnect-required connection" do
        service.call

        expect(service).not_to be_success
        expect(google_connection.reload.status).to eq("reauth_required")
      end
    end

    context "when the expired connection has no refresh token" do
      let(:access_token_expires_at) { 1.minute.ago }
      let(:google_connection) { create(:google_connection, access_token_expires_at:, refresh_token: nil) }

      it "returns a reconnect-required connection without creating an API client" do
        service.call

        expect(service).not_to be_success
        expect(google_connection.reload.status).to eq("reauth_required")
        expect(Google::Client).not_to have_received(:new)
      end
    end
  end
end
