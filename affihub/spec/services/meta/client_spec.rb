require "rails_helper"

RSpec.describe Meta::Client, type: :service do
  describe "#exchange_code" do
    it "returns the token response from the configured Graph API version" do
      stub_request(:get, "https://graph.facebook.com/v26.0/oauth/access_token")
        .with(query: {
          "client_id" => "affihub-test-client",
          "client_secret" => "affihub-test-secret",
          "code" => "oauth-code",
          "redirect_uri" => "http://localhost:3000/auth/facebook/callback"
        })
        .to_return(body: { access_token: "user-token", expires_in: 5_184_000 }.to_json)

      response = described_class.new.exchange_code(
        code: "oauth-code", redirect_uri: "http://localhost:3000/auth/facebook/callback"
      )

      expect(response).to eq("access_token" => "user-token", "expires_in" => 5_184_000)
    end
  end

  describe "#pages" do
    it "returns the Page list authorized for the connected profile" do
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: { "fields" => "id,name,access_token,tasks", "access_token" => "user-token" })
        .to_return(body: { data: [ { id: "page-1", name: "Page Một", access_token: "page-token" } ] }.to_json)

      pages = described_class.new.pages(access_token: "user-token")

      expect(pages).to eq([ { "id" => "page-1", "name" => "Page Một", "access_token" => "page-token" } ])
    end
  end

  describe "#pages with Instagram provider" do
    it "returns Page tokens and Instagram Business account mappings from the connected profile" do
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: {
          "fields" => "id,name,access_token,tasks,instagram_business_account{id,account_type}",
          "access_token" => "instagram-user-token"
        })
        .to_return(body: { data: [
          {
            id: "page-1",
            name: "Page Một",
            access_token: "page-token",
            tasks: [ "CREATE_CONTENT" ],
            instagram_business_account: { id: "ig-business-1", account_type: "BUSINESS" }
          }
        ] }.to_json)

      pages = described_class.new(provider: :instagram).pages(access_token: "instagram-user-token")

      expect(pages).to eq([
        {
          "id" => "page-1",
          "name" => "Page Một",
          "access_token" => "page-token",
          "tasks" => [ "CREATE_CONTENT" ],
          "instagram_business_account" => { "id" => "ig-business-1", "account_type" => "BUSINESS" }
        }
      ])
    end
  end

  describe "#instagram_content_publishing_limit" do
    it "returns the current quota and duration from Meta" do
      stub_request(:get, "https://graph.facebook.com/v26.0/ig-business-1/content_publishing_limit")
        .with(query: {
          "fields" => "quota_usage,config",
          "access_token" => "instagram-page-token"
        })
        .to_return(body: {
          data: [ { quota_usage: 12, config: { quota_total: 80, quota_duration: 86_400 } } ]
        }.to_json)

      response = described_class.new(provider: :instagram).instagram_content_publishing_limit(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token"
      )

      expect(response).to eq(
        "data" => [ { "quota_usage" => 12, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } } ]
      )
    end
  end

  describe "#start_instagram_reel_upload" do
    it "creates a resumable local-file container without a public video URL" do
      stub_request(:post, "https://graph.facebook.com/v26.0/ig-business-1/media")
        .with(query: {
          "media_type" => "REELS",
          "upload_type" => "resumable",
          "caption" => "Caption riêng",
          "access_token" => "instagram-page-token"
        })
        .to_return(body: {
          id: "creation-1",
          uri: "https://rupload.facebook.com/ig-api-upload/v26.0/creation-1?sig=signed-upload-secret"
        }.to_json)

      response = described_class.new(provider: :instagram).start_instagram_reel_upload(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token",
        caption: "Caption riêng"
      )

      expect(response).to eq(
        "id" => "creation-1",
        "uri" => "https://rupload.facebook.com/ig-api-upload/v26.0/creation-1?sig=signed-upload-secret"
      )
    end
  end

  describe "#upload_instagram_reel" do
    it "uploads the local video bytes to the provider upload URI" do
      upload_url = "https://rupload.facebook.com/ig-api-upload/v26.0/creation-1"
      stub_request(:post, upload_url)
        .with(headers: {
          "Authorization" => "OAuth instagram-page-token",
          "offset" => "0",
          "file_size" => "15"
        })
        .to_return(body: { success: true }.to_json)

      response = described_class.new(provider: :instagram).upload_instagram_reel(
        upload_url:,
        page_access_token: "instagram-page-token",
        file: StringIO.new("local video data"),
        file_size: 15
      )

      expect(response).to eq("success" => true)
    end
  end

  describe "#instagram_reel_status" do
    it "returns the current upload container status" do
      stub_request(:get, "https://graph.facebook.com/v26.0/creation-1")
        .with(query: {
          "fields" => "status_code,status",
          "access_token" => "instagram-page-token"
        })
        .to_return(body: { status_code: "FINISHED", status: "Finished: video processing completed" }.to_json)

      response = described_class.new(provider: :instagram).instagram_reel_status(
        creation_id: "creation-1",
        page_access_token: "instagram-page-token"
      )

      expect(response).to eq(
        "status_code" => "FINISHED",
        "status" => "Finished: video processing completed"
      )
    end
  end

  describe "#publish_instagram_reel" do
    it "publishes the finished container and returns Meta's media ID" do
      stub_request(:post, "https://graph.facebook.com/v26.0/ig-business-1/media_publish")
        .with(query: {
          "creation_id" => "creation-1",
          "access_token" => "instagram-page-token"
        })
        .to_return(body: { id: "instagram-media-1" }.to_json)

      response = described_class.new(provider: :instagram).publish_instagram_reel(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token",
        creation_id: "creation-1"
      )

      expect(response).to eq("id" => "instagram-media-1")
    end
  end

  describe "#instagram_media" do
    it "returns the provider media ID and permalink" do
      stub_request(:get, "https://graph.facebook.com/v26.0/instagram-media-1")
        .with(query: {
          "fields" => "id,permalink",
          "access_token" => "instagram-page-token"
        })
        .to_return(body: { id: "instagram-media-1", permalink: "https://www.instagram.com/reel/abc/" }.to_json)

      response = described_class.new(provider: :instagram).instagram_media(
        media_id: "instagram-media-1",
        page_access_token: "instagram-page-token"
      )

      expect(response).to eq("id" => "instagram-media-1", "permalink" => "https://www.instagram.com/reel/abc/")
    end
  end

  describe "#page_video" do
    it "returns the Page video ID and source from the configured Graph API version" do
      stub_request(:get, "https://graph.facebook.com/v26.0/video-1")
        .with(query: { "fields" => "id,source", "access_token" => "page-token" })
        .to_return(body: { id: "video-1", source: "https://video.cdn.example/download" }.to_json)

      video = described_class.new.page_video(video_id: "video-1", page_access_token: "page-token")

      expect(video).to eq("id" => "video-1", "source" => "https://video.cdn.example/download")
    end
  end

  describe "#start_reel_upload" do
    it "returns the video ID and upload URL from the selected Page" do
      stub_request(:post, "https://graph.facebook.com/v26.0/page-1/video_reels")
        .with(query: { "upload_phase" => "start", "access_token" => "page-token" })
        .to_return(body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json)

      response = described_class.new.start_reel_upload(page_id: "page-1", page_access_token: "page-token")

      expect(response).to eq("video_id" => "video-1", "upload_url" => "https://rupload.facebook.com/upload/video-1")
    end

    it "encodes the selected Page ID as one Graph API path segment" do
      stub_request(:post, "https://graph.facebook.com/v26.0/page%2Fone/video_reels")
        .with(query: { "upload_phase" => "start", "access_token" => "page-token" })
        .to_return(body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json)

      response = described_class.new.start_reel_upload(page_id: "page/one", page_access_token: "page-token")

      expect(response.fetch("video_id")).to eq("video-1")
    end
  end

  describe "#upload_reel" do
    it "returns the provider upload acknowledgement for the complete file" do
      file = StringIO.new("sample mp4 bytes")
      stub_request(:post, "https://rupload.facebook.com/video-upload/v26.0/video-1")
        .with(headers: { "Authorization" => "OAuth page-token", "offset" => "0", "file_size" => "16" })
        .to_return(body: { success: true }.to_json)

      response = described_class.new.upload_reel(
        upload_url: "https://rupload.facebook.com/video-upload/v26.0/video-1",
        page_access_token: "page-token", file:, file_size: 16
      )

      expect(response).to eq("success" => true)
    end

    context "when the upload URL is outside Meta's upload host" do
      it "rejects the URL without sending the video file" do
        upload_url = "https://127.0.0.1/internal/upload"
        upload_request = stub_request(:post, upload_url).to_return(body: { success: true }.to_json)

        expect do
          described_class.new.upload_reel(
            upload_url:,
            page_access_token: "page-token",
            file: StringIO.new("sample mp4 bytes"),
            file_size: 16
          )
        end.to raise_error(described_class::Error, "invalid_upload_url")
        expect(upload_request).not_to have_been_requested
      end
    end
  end

  describe "#finish_reel_upload" do
    it "returns the publish acknowledgement for the uploaded video" do
      stub_request(:post, "https://graph.facebook.com/v26.0/page-1/video_reels")
        .with(query: {
          "upload_phase" => "finish",
          "video_id" => "video-1",
          "video_state" => "PUBLISHED",
          "description" => "Caption",
          "access_token" => "page-token"
        })
        .to_return(body: { success: true }.to_json)

      response = described_class.new.finish_reel_upload(
        page_id: "page-1", page_access_token: "page-token", video_id: "video-1", caption: "Caption"
      )

      expect(response).to eq("success" => true)
    end
  end

  describe "#reel_status" do
    it "returns the Reel status and permalink fields from Meta" do
      stub_request(:get, "https://graph.facebook.com/v26.0/video-1")
        .with(query: { "fields" => "status,permalink_url", "access_token" => "page-token" })
        .to_return(
          body: {
            status: {
              video_status: "ready",
              publishing_phase: { status: "complete" }
            },
            permalink_url: "https://facebook.com/reel/1"
          }.to_json
        )

      status = described_class.new.reel_status(video_id: "video-1", page_access_token: "page-token")

      expect(status).to eq(
        "status" => {
          "video_status" => "ready",
          "publishing_phase" => { "status" => "complete" }
        },
        "permalink_url" => "https://facebook.com/reel/1"
      )
    end
  end

  describe "provider errors" do
    it "returns a safe error code without echoing the token or provider message" do
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: { "fields" => "id,name,access_token,tasks", "access_token" => "user-token-secret" })
        .to_return(status: 400, body: { error: { code: 190, message: "Invalid user-token-secret" } }.to_json)

      expect { described_class.new.pages(access_token: "user-token-secret") }
        .to raise_error(described_class::Error, "graph_api_190")
    end
  end

  describe "sensitive request data" do
    it "returns no log entries containing a Page token or signed upload URL" do
      page_access_token = "page-token-secret"
      upload_url = "https://rupload.facebook.com/video-upload/v26.0/video-1?signature=signed-url-secret"
      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(log_output)
      stub_request(:post, upload_url).to_return(status: 500, body: { error: { message: page_access_token } }.to_json)

      expect { described_class.new.upload_reel(upload_url:, page_access_token:, file: StringIO.new("mp4"), file_size: 3) }
        .to raise_error(described_class::Error, "graph_api_http_500")
      expect(log_output.string).not_to match(Regexp.union(page_access_token, upload_url))
    ensure
      Rails.logger = original_logger
    end
  end
end
