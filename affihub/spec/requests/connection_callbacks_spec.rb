require "rails_helper"

RSpec.describe "Connection callbacks", type: :request do
  describe "GET /auth/:provider/callback" do
    context "when a Google OAuth code is available" do
      let(:authorization_params) { Rack::Utils.parse_query(URI(response.location).query) }
      let(:access_token) { "google-response-access-secret" }
      let(:refresh_token) { "google-response-refresh-secret" }

      before do
        host! "127.0.0.1:3000"
        stub_request(:post, "https://oauth2.googleapis.com/token")
          .to_return(body: {
            access_token:,
            refresh_token:,
            expires_in: 3600,
            scope: "openid email https://www.googleapis.com/auth/drive.file"
          }.to_json)
        stub_request(:get, "https://openidconnect.googleapis.com/v1/userinfo")
          .with(headers: { "Authorization" => "Bearer #{access_token}" })
          .to_return(body: { sub: "google-user-1", email: "creator@example.test" }.to_json)
        post google_connections_path, params: { integration: "drive" }
      end

      it "redirects after storing the selected Google integration" do
        get connection_callback_path(provider: "google"), params: {
          state: authorization_params.fetch("state"),
          code: "google-oauth-code"
        }

        expect(response).to be_redirect
        google_connection = GoogleConnection.find_by!(integration: "drive", google_account_id: "google-user-1")
        expect(google_connection.attributes.slice("email", "status", "scopes")).to eq(
          "email" => "creator@example.test",
          "status" => "connected",
          "scopes" => [ "openid", "email", "https://www.googleapis.com/auth/drive.file" ]
        )
      end

      it "does not expose OAuth tokens in the callback response or logs" do
        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        get connection_callback_path(provider: "google"), params: {
          state: authorization_params.fetch("state"),
          code: "google-oauth-code"
        }

        secrets = Regexp.union(access_token, refresh_token)
        expect(response.body).not_to match(secrets)
        expect(response.location).not_to match(secrets)
        expect(log_output.string).not_to match(secrets)
      ensure
        Rails.logger = original_logger
      end
    end

    context "when a Facebook OAuth code is available" do
      let(:authorization_params) { Rack::Utils.parse_query(URI(response.location).query) }

      before do
        host! "localhost:3000"
        post social_connections_path, params: { provider: "facebook" }
        stub_request(:get, %r{graph.facebook.com/v26.0/oauth/access_token})
          .to_return(body: { access_token: "response-secret-token", expires_in: 5_184_000 }.to_json)
        stub_request(:get, %r{graph.facebook.com/v26.0/me})
          .to_return(body: { id: "facebook-user-1", name: "Page Owner" }.to_json)
      end

      it "redirects after connecting without exposing the exchanged credential" do
        get connection_callback_path(provider: "facebook"), params: {
          state: authorization_params.fetch("state"),
          code: "oauth-code"
        }

        expect(response).to be_redirect
        expect(SocialConnection.count).to eq(1)
        expect(response.body).not_to match(Regexp.escape("response-secret-token"))
        expect(response.location).not_to match(Regexp.escape("response-secret-token"))
      end
    end

    context "when a TikTok OAuth code is available" do
      let(:access_token) { "tiktok-response-access-secret" }
      let(:refresh_token) { "tiktok-response-refresh-secret" }
      let(:authorization_params) { Rack::Utils.parse_query(URI(response.location).query) }

      before do
        host! "127.0.0.1:3000"
        post social_connections_path, params: { provider: "tiktok" }
        stub_request(:post, "https://open.tiktokapis.com/v2/oauth/token/")
          .to_return(body: {
            open_id: "creator-1",
            access_token:,
            refresh_token:,
            expires_in: 86_400,
            refresh_expires_in: 31_536_000,
            scope: "user.info.basic,video.publish"
          }.to_json)
        stub_request(:get, "https://open.tiktokapis.com/v2/user/info/")
        .with(query: { "fields" => "open_id,display_name" })
          .to_return(body: {
            data: { user: { open_id: "creator-1", display_name: "Nhà sáng tạo" } },
            error: { code: "ok" }
          }.to_json)
      end

      it "redirects after connecting the TikTok creator" do
        get connection_callback_path(provider: "tiktok"), params: {
          state: authorization_params.fetch("state"),
          code: "oauth-code"
        }

        expect(response).to be_redirect
        expect(SocialConnection.find_by!(provider: "tiktok").name).to eq("Nhà sáng tạo")
      end

      it "does not expose the exchanged access or refresh tokens in the response" do
        get connection_callback_path(provider: "tiktok"), params: {
          state: authorization_params.fetch("state"),
          code: "oauth-code"
        }

        expect(response.body).not_to match(Regexp.union(access_token, refresh_token))
        expect(response.location).not_to match(Regexp.union(access_token, refresh_token))
      end

      it "does not write the exchanged access or refresh tokens to logs" do
        log_output = StringIO.new
        original_logger = Rails.logger
        Rails.logger = ActiveSupport::Logger.new(log_output)

        get connection_callback_path(provider: "tiktok"), params: {
          state: authorization_params.fetch("state"),
          code: "oauth-code"
        }

        expect(log_output.string).not_to match(Regexp.union(access_token, refresh_token))
      ensure
        Rails.logger = original_logger
      end
    end
  end
end
