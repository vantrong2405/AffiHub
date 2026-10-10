require "rails_helper"

RSpec.describe Youtube::Client, type: :service do
  describe "#refresh_token" do
    it "returns Google's refreshed access token and rotated refresh token" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .with(body: {
          "client_id" => "affihub-youtube-test-client",
          "grant_type" => "refresh_token",
          "refresh_token" => "youtube-refresh-secret"
        })
        .to_return(body: {
          access_token: "youtube-new-access-secret",
          refresh_token: "youtube-new-refresh-secret",
          expires_in: 3600
        }.to_json)

      result = described_class.new.refresh_token(refresh_token: "youtube-refresh-secret")

      expect(result).to eq(
        "access_token" => "youtube-new-access-secret",
        "refresh_token" => "youtube-new-refresh-secret",
        "expires_in" => 3600
      )
    end

    it "raises the configured invalid-grant code without exposing Google's error description" do
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .with(body: {
          "client_id" => "affihub-youtube-test-client",
          "grant_type" => "refresh_token",
          "refresh_token" => "youtube-refresh-secret"
        })
        .to_return(status: 400, body: {
          error: "invalid_grant",
          error_description: "youtube-refresh-secret was revoked"
        }.to_json)

      expect do
        described_class.new.refresh_token(refresh_token: "youtube-refresh-secret")
      end.to raise_error(described_class::Error, "invalid_grant")
    end
  end

  describe "#channels" do
    it "returns every owned channel across paginated responses" do
      stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
        .with(query: { "part" => "snippet", "mine" => "true", "maxResults" => "50" })
        .with(headers: { "Authorization" => "Bearer youtube-access-secret" })
        .to_return(body: {
          items: [ { id: "channel-1", snippet: { title: "Kênh Một" } } ],
          nextPageToken: "page-2-token"
        }.to_json)
      stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
        .with(query: { "part" => "snippet", "mine" => "true", "maxResults" => "50", "pageToken" => "page-2-token" })
        .with(headers: { "Authorization" => "Bearer youtube-access-secret" })
        .to_return(body: { items: [ { id: "channel-2", snippet: { title: "Kênh Hai" } } ] }.to_json)

      channels = described_class.new.channels(access_token: "youtube-access-secret")

      expect(channels).to eq([
        { "id" => "channel-1", "name" => "Kênh Một" },
        { "id" => "channel-2", "name" => "Kênh Hai" }
      ])
    end

    it "raises a safe quota error without exposing the provider response" do
      stub_request(:get, "https://www.googleapis.com/youtube/v3/channels")
        .with(query: { "part" => "snippet", "mine" => "true", "maxResults" => "50" })
        .to_return(status: 403, body: {
          error: { errors: [ { reason: "quotaExceeded", message: "youtube-access-secret" } ] }
        }.to_json)

      expect { described_class.new.channels(access_token: "youtube-access-secret") }
        .to raise_error(described_class::Error, "quota_exhausted")
    end
  end

  describe "#start_resumable_upload" do
    it "returns the provider session URI after starting videos.insert with approved metadata" do
      session_uri = "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-secret"
      metadata = {
        "snippet" => { "title" => "Video mẫu", "description" => "Mô tả", "tags" => [ "mẫu" ] },
        "status" => {
          "privacyStatus" => "private",
          "selfDeclaredMadeForKids" => false,
          "containsSyntheticMedia" => true
        }
      }
      stub_request(:post, "https://www.googleapis.com/upload/youtube/v3/videos")
        .with(
          query: { "uploadType" => "resumable", "part" => "snippet,status" },
          headers: {
            "Authorization" => "Bearer youtube-access-secret",
            "Content-Type" => "application/json; charset=UTF-8",
            "X-Upload-Content-Length" => "1024",
            "X-Upload-Content-Type" => "video/mp4"
          },
          body: metadata.to_json
        )
        .to_return(status: 200, headers: { "Location" => session_uri })

      result = described_class.new.start_resumable_upload(
        access_token: "youtube-access-secret", metadata:, file_size: 1024, content_type: "video/mp4"
      )

      expect(result).to eq(session_uri)
      expect(YoutubeQuotaCounter.find_by!(bucket: "videos.insert").requests_count).to eq(1)
    end

    it "raises a local quota error before starting a session when videos.insert is exhausted" do
      configuration = Rails.application.config_for(:youtube).deep_symbolize_keys
      bucket = configuration.dig(:quota, :buckets, :videos_insert)
      create(:youtube_quota_counter, bucket: bucket.fetch(:method), requests_count: bucket.fetch(:daily_limit))
      request = stub_request(:post, "https://www.googleapis.com/upload/youtube/v3/videos")

      expect do
        described_class.new.start_resumable_upload(
          access_token: "youtube-access-secret", metadata: {}, file_size: 1024, content_type: "video/mp4"
        )
      end.to raise_error(described_class::Error, "quota_exhausted")

      expect(request).not_to have_been_made
    end

    it "raises a safe error when videos.insert omits its session URI" do
      stub_request(:post, "https://www.googleapis.com/upload/youtube/v3/videos")
        .with(query: { "uploadType" => "resumable", "part" => "snippet,status" })
        .to_return(status: 200)

      expect do
        described_class.new.start_resumable_upload(
          access_token: "youtube-access-secret", metadata: {}, file_size: 1024, content_type: "video/mp4"
        )
      end.to raise_error(described_class::Error, "missing_upload_session")
    end

    it "rejects a session URI outside the configured Google upload host" do
      stub_request(:post, "https://www.googleapis.com/upload/youtube/v3/videos")
        .with(query: { "uploadType" => "resumable", "part" => "snippet,status" })
        .to_return(status: 200, headers: { "Location" => "https://attacker.example/upload?secret=signed-secret" })

      expect do
        described_class.new.start_resumable_upload(
          access_token: "youtube-access-secret", metadata: {}, file_size: 1024, content_type: "video/mp4"
        )
      end.to raise_error(described_class::Error, "invalid_upload_session")
    end
  end

  describe "#upload_status" do
    let(:session_uri) do
      "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-secret"
    end

    it "returns the next byte offset from a 308 Range response" do
      stub_request(:put, session_uri)
        .with(
          headers: {
            "Authorization" => "Bearer youtube-access-secret",
            "Content-Length" => "0",
            "Content-Range" => "bytes */10"
          },
          body: ""
        )
        .to_return(status: 308, headers: { "Range" => "bytes=0-4" })

      result = described_class.new.upload_status(
        access_token: "youtube-access-secret", session_uri:, file_size: 10
      )

      expect(result).to eq(uploaded_bytes: 5, video_id: nil)
    end

    it "returns zero bytes when a 308 response has no Range header" do
      stub_request(:put, session_uri)
        .to_return(status: 308)

      result = described_class.new.upload_status(
        access_token: "youtube-access-secret", session_uri:, file_size: 10
      )

      expect(result).to eq(uploaded_bytes: 0, video_id: nil)
    end

    it "returns the provider video ID when status reconciliation finds a completed upload" do
      stub_request(:put, session_uri)
        .to_return(status: 201, body: { id: "youtube-video-1" }.to_json)

      result = described_class.new.upload_status(
        access_token: "youtube-access-secret", session_uri:, file_size: 10
      )

      expect(result).to eq(uploaded_bytes: 10, video_id: "youtube-video-1")
    end

    it "raises a safe error when YouTube reports a byte range beyond the render size" do
      stub_request(:put, session_uri)
        .to_return(status: 308, headers: { "Range" => "bytes=0-15" })

      expect do
        described_class.new.upload_status(
          access_token: "youtube-access-secret", session_uri:, file_size: 10
        )
      end.to raise_error(described_class::Error, "invalid_upload_range")
    end

    it "raises a channel upload limit error separately from project quota" do
      stub_request(:put, session_uri)
        .to_return(status: 403, body: {
          error: { errors: [ { reason: "uploadLimitExceeded", message: "youtube-access-secret" } ] }
        }.to_json)

      expect do
        described_class.new.upload_status(
          access_token: "youtube-access-secret", session_uri:, file_size: 10
        )
      end.to raise_error(described_class::Error, "upload_limit_exhausted")
    end
  end

  describe "#upload_remaining" do
    let(:session_uri) do
      "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-secret"
    end

    it "returns the provider video ID after uploading the unreceived file suffix" do
      stub_request(:put, session_uri)
        .with(
          headers: {
            "Authorization" => "Bearer youtube-access-secret",
            "Content-Length" => "5",
            "Content-Type" => "video/mp4",
            "Content-Range" => "bytes 5-9/10"
          },
          body: "56789"
        )
        .to_return(status: 201, body: { id: "youtube-video-1" }.to_json)

      result = described_class.new.upload_remaining(
        access_token: "youtube-access-secret",
        session_uri:,
        file: StringIO.new("0123456789"),
        file_size: 10,
        offset: 5,
        content_type: "video/mp4"
      )

      expect(result).to eq(uploaded_bytes: 10, video_id: "youtube-video-1")
    end

    it "returns the next byte offset after an incomplete upload acknowledgement" do
      stub_request(:put, session_uri)
        .with(headers: { "Content-Range" => "bytes 0-9/10" }, body: "0123456789")
        .to_return(status: 308, headers: { "Range" => "bytes=0-5" })

      result = described_class.new.upload_remaining(
        access_token: "youtube-access-secret",
        session_uri:,
        file: StringIO.new("0123456789"),
        file_size: 10,
        offset: 0,
        content_type: "video/mp4"
      )

      expect(result).to eq(uploaded_bytes: 6, video_id: nil)
    end

    it "rejects a signed upload URI on another host before sending file bytes" do
      expect do
        described_class.new.upload_remaining(
          access_token: "youtube-access-secret",
          session_uri: "https://attacker.example/upload?upload_id=signed-secret",
          file: StringIO.new("0123456789"),
          file_size: 10,
          offset: 0,
          content_type: "video/mp4"
        )
      end.to raise_error(described_class::Error, "invalid_upload_session")
    end
  end

  describe "#video_status" do
    it "returns provider processing and privacy fields for the exact uploaded video" do
      stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: { "part" => "processingDetails,status,snippet", "id" => "video-1" })
        .with(headers: { "Authorization" => "Bearer youtube-access-secret" })
        .to_return(body: { items: [
          {
            id: "video-1",
            snippet: { channelId: "channel-1" },
            processingDetails: { processingStatus: "succeeded" },
            status: { privacyStatus: "private" }
          }
        ] }.to_json)

      result = described_class.new.video_status(
        access_token: "youtube-access-secret", video_id: "video-1"
      )

      expect(result).to eq(
        "id" => "video-1",
        "snippet" => { "channelId" => "channel-1" },
        "processingDetails" => { "processingStatus" => "succeeded" },
        "status" => { "privacyStatus" => "private" }
      )
    end

    it "raises a safe error when YouTube does not return the requested video" do
      stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: { "part" => "processingDetails,status,snippet", "id" => "video-1" })
        .to_return(body: { items: [] }.to_json)

      expect do
        described_class.new.video_status(access_token: "youtube-access-secret", video_id: "video-1")
      end.to raise_error(described_class::Error, "video_not_found")
    end
  end
end
