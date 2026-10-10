require "rails_helper"

RSpec.describe ConnectionCallbacks::ShowService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    context "when completing a Facebook OAuth attempt" do
      let(:session) { {} }
      let(:oauth_request) { SocialConnections::CreateService.new(provider: "facebook", session:) }
      let(:callback_params) { { state: oauth_request.state, code: "oauth-code" } }
      let(:callback_url) { "http://localhost:3000/auth/facebook/callback" }
      let(:callback_options) do
        { provider: "facebook", params: callback_params, session:, callback_url: }
      end
      let(:service) { described_class.new(**callback_options) }

      before do
        oauth_request.call
      end

      it "rejects a callback received in a different browser session" do
        callback_service = described_class.new(**callback_options.merge(session: {}))

        expect(callback_service.call).to eq(false)
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

        it "persists the access token encrypted" do
          service.call
          social_connection = SocialConnection.last

          expect(social_connection.access_token).to eq("facebook-user-secret")
          expect(social_connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("facebook-user-secret"))
        end

        it "does not write the access token to logs" do
          service.call

          expect(log_output.string).not_to match(Regexp.escape("facebook-user-secret"))
        end

        context "when the callback has already succeeded" do
          before do
            expect(service.call).to be(true)
          end

          it "rejects replay of the consumed OAuth state" do
            replay_service = described_class.new(**callback_options)

            replay_service.call

            expect(replay_service).not_to be_success
          end
        end
      end

      it "rejects a state that has expired" do
        travel_to(1.hour.from_now) { service.call }

        expect(service).not_to be_success
        expect(SocialConnection.count).to eq(0)
      end

      it "rejects a callback URL outside the configured allowlist" do
        callback_service = described_class.new(
          **callback_options.merge(callback_url: "https://attacker.example/auth/facebook/callback")
        )

        callback_service.call

        expect(callback_service).not_to be_success
        expect(SocialConnection.count).to eq(0)
      end
    end

    context "when completing a TikTok OAuth attempt" do
      let(:callback_url) { "http://127.0.0.1:3000/auth/tiktok/callback" }
      let(:state) { "tiktok-oauth-state" }
      let(:state_digest) { Digest::SHA256.hexdigest(state) }
      let(:session) do
        {
          "social_oauth_attempts" => {
            state_digest => {
              "provider" => "tiktok",
              "redirect_uri" => callback_url,
              "expires_at" => 10.minutes.from_now.iso8601(6),
              "code_verifier" => "tiktok-pkce-verifier"
            }
          }
        }
      end
      let(:callback_options) do
        {
          provider: "tiktok",
          params: { state:, code: "oauth-code" },
          session:,
          callback_url:
        }
      end

      context "when TikTok accepts the callback" do
        let(:access_token) { "tiktok-user-access-secret" }
        let(:refresh_token) { "tiktok-user-refresh-secret" }

        before do
          stub_request(:post, "https://open.tiktokapis.com/v2/oauth/token/")
            .with(body: {
              "client_key" => "tiktok-test-client",
              "client_secret" => "tiktok-test-secret",
              "code" => "oauth-code",
              "code_verifier" => "tiktok-pkce-verifier",
              "grant_type" => "authorization_code",
              "redirect_uri" => callback_url
            })
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
            .with(headers: { "Authorization" => "Bearer #{access_token}" })
            .to_return(body: {
              data: { user: { open_id: "creator-1", display_name: "Nhà sáng tạo" } },
              error: { code: "ok" }
            }.to_json)
        end

        it "stores encrypted TikTok credentials and creates the creator destination" do
          callback_service = described_class.new(**callback_options)

          expect(callback_service.call).to eq(true)

          connection = SocialConnection.find_by!(provider: "tiktok", external_user_id: "creator-1")
          destination = connection.social_destinations.sole

          expect(connection.access_token).to eq(access_token)
          expect(connection.refresh_token).to eq(refresh_token)
          expect(connection.scopes).to eq(%w[user.info.basic video.publish])
          expect(connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape(access_token))
          expect(connection.read_attribute_before_type_cast(:refresh_token)).not_to match(Regexp.escape(refresh_token))
          expect(destination).to have_attributes(
            provider: "tiktok",
            external_id: "creator-1",
            name: "Nhà sáng tạo",
            access_token:
          )
        end
      end

      it "rejects a callback received in a different browser session" do
        callback_service = described_class.new(**callback_options.merge(session: {}))

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.count).to eq(0)
      end

      it "rejects a state that has expired" do
        callback_service = described_class.new(**callback_options)

        travel_to(11.minutes.from_now) do
          expect(callback_service.call).to eq(false)
        end

        expect(SocialConnection.count).to eq(0)
      end

      it "consumes state when the user cancels OAuth" do
        callback_service = described_class.new(
          **callback_options.merge(params: { state:, error: "access_denied" })
        )

        expect(callback_service.call).to eq(false)
        expect(session.fetch("social_oauth_attempts")).to eq({})
      end

      it "does not create a connection when the user cancels OAuth" do
        callback_service = described_class.new(
          **callback_options.merge(params: { state:, error: "access_denied" })
        )

        callback_service.call

        expect(SocialConnection.count).to eq(0)
      end

      context "when the user already canceled OAuth" do
        before do
          callback_service = described_class.new(
            **callback_options.merge(params: { state:, error: "access_denied" })
          )
          expect(callback_service.call).to eq(false)
        end

        it "rejects replay of the consumed state" do
          replay_callback = described_class.new(
            **callback_options.merge(params: { state:, code: "oauth-code" })
          )

          expect(replay_callback.call).to eq(false)
        end
      end

      it "rejects a callback URL outside the TikTok allowlist" do
        callback_service = described_class.new(
          **callback_options.merge(callback_url: "https://attacker.example/auth/tiktok/callback")
        )

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.count).to eq(0)
      end
    end

    context "when completing an Instagram Facebook Login attempt" do
      let(:session) { {} }
      let(:oauth_request) { SocialConnections::CreateService.new(provider: "instagram", session:) }
      let(:callback_url) { "http://localhost:3000/auth/instagram/callback" }
      let(:callback_options) do
        {
          provider: "instagram",
          params: { state: oauth_request.state, code: "instagram-code" },
          session:,
          callback_url:
        }
      end

      before do
        oauth_request.call
        stub_request(:get, %r{graph.facebook.com/v26.0/oauth/access_token})
          .with(query: {
            "client_id" => "affihub-instagram-test-client",
            "client_secret" => "affihub-instagram-test-secret",
            "code" => "instagram-code",
            "redirect_uri" => callback_url
          })
          .to_return(body: { access_token: "instagram-user-secret", expires_in: 5_184_000 }.to_json)
        stub_request(:get, %r{graph.facebook.com/v26.0/me})
          .to_return(body: { id: "facebook-owner-1", name: "Chủ Page" }.to_json)
      end

      it "returns an encrypted Instagram connection without selecting a Page automatically" do
        callback_service = described_class.new(**callback_options)

        expect(callback_service.call).to eq(true)

        social_connection = SocialConnection.find_by!(provider: "instagram", external_user_id: "facebook-owner-1")
        expect(social_connection.access_token).to eq("instagram-user-secret")
        expect(social_connection.read_attribute_before_type_cast(:access_token)).not_to match("instagram-user-secret")
        expect(social_connection.social_destinations.count).to eq(0)
      end

      it "returns false for a callback from a different browser session" do
        callback_service = described_class.new(**callback_options.merge(session: {}))

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.where(provider: "instagram").count).to eq(0)
      end

      it "returns false when the Instagram state has expired" do
        callback_service = described_class.new(**callback_options)

        travel_to(11.minutes.from_now) do
          expect(callback_service.call).to eq(false)
        end
        expect(SocialConnection.where(provider: "instagram").count).to eq(0)
      end

      it "returns false for a callback outside the Instagram allowlist" do
        callback_service = described_class.new(
          **callback_options.merge(callback_url: "https://attacker.example/auth/instagram/callback")
        )

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.where(provider: "instagram").count).to eq(0)
      end

      it "returns false when the consumed Instagram state is replayed" do
        first_callback = described_class.new(**callback_options)
        expect(first_callback.call).to eq(true)

        replay_callback = described_class.new(**callback_options)

        expect(replay_callback.call).to eq(false)
        expect(SocialConnection.where(provider: "instagram").count).to eq(1)
      end
    end

    context "when completing a YouTube desktop OAuth attempt" do
      let(:session) { {} }
      let(:oauth_request) { SocialConnections::CreateService.new(provider: "youtube", session:) }
      let(:callback_url) { "http://127.0.0.1:3000/auth/youtube/callback" }
      let(:callback_options) do
        {
          provider: "youtube",
          params: { state: oauth_request.state, code: "youtube-code" },
          session:,
          callback_url:
        }
      end

      before do
        expect(oauth_request.call).to eq(true)
        stub_request(:post, "https://oauth2.googleapis.com/token")
          .with(body: {
            "client_id" => "affihub-youtube-test-client",
            "code" => "youtube-code",
            "code_verifier" => session.fetch("social_oauth_attempts")
              .fetch(Digest::SHA256.hexdigest(oauth_request.state)).fetch("code_verifier"),
            "grant_type" => "authorization_code",
            "redirect_uri" => callback_url
          })
          .to_return(body: {
            access_token: "youtube-access-secret",
            refresh_token: "youtube-refresh-secret",
            expires_in: 3600,
            scope: "openid profile https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly"
          }.to_json)
        stub_request(:get, "https://openidconnect.googleapis.com/v1/userinfo")
          .with(headers: { "Authorization" => "Bearer youtube-access-secret" })
          .to_return(body: { sub: "google-sub-1", name: "Chủ kênh" }.to_json)
      end

      it "returns an encrypted Google connection without selecting a channel" do
        callback_service = described_class.new(**callback_options)

        expect(callback_service.call).to eq(true)

        social_connection = SocialConnection.find_by!(provider: "youtube", external_user_id: "google-sub-1")
        expect(social_connection.name).to eq("Chủ kênh")
        expect(social_connection.access_token).to eq("youtube-access-secret")
        expect(social_connection.refresh_token).to eq("youtube-refresh-secret")
        expect(social_connection.read_attribute_before_type_cast(:access_token)).not_to match("youtube-access-secret")
        expect(social_connection.read_attribute_before_type_cast(:refresh_token)).not_to match("youtube-refresh-secret")
        expect(social_connection.social_destinations.count).to eq(0)
      end

      it "returns false for a callback from another browser session" do
        callback_service = described_class.new(**callback_options.merge(session: {}))

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.where(provider: "youtube").count).to eq(0)
      end

      it "returns false for an expired OAuth state" do
        callback_service = described_class.new(**callback_options)

        travel_to(11.minutes.from_now) do
          expect(callback_service.call).to eq(false)
        end
        expect(SocialConnection.where(provider: "youtube").count).to eq(0)
      end

      it "returns false for a callback outside the YouTube allowlist" do
        callback_service = described_class.new(
          **callback_options.merge(callback_url: "https://attacker.example/auth/youtube/callback")
        )

        expect(callback_service.call).to eq(false)
        expect(SocialConnection.where(provider: "youtube").count).to eq(0)
      end

      it "returns false when the YouTube state is replayed" do
        first_callback = described_class.new(**callback_options)
        expect(first_callback.call).to eq(true)

        replay_callback = described_class.new(**callback_options)

        expect(replay_callback.call).to eq(false)
        expect(SocialConnection.where(provider: "youtube").count).to eq(1)
      end
    end
  end
end
