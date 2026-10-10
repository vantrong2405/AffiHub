require "rails_helper"

RSpec.describe TikTok::Client, type: :service do
  describe "#exchange_code" do
    it "returns exchanged credentials for the configured client and PKCE verifier" do
      stub_request(:post, "https://open.tiktokapis.com/v2/oauth/token/")
        .with(body: {
          "client_key" => "tiktok-test-client",
          "client_secret" => "tiktok-test-secret",
          "code" => "authorization-code",
          "code_verifier" => "tiktok-code-verifier",
          "grant_type" => "authorization_code",
          "redirect_uri" => "http://127.0.0.1:3000/auth/tiktok/callback"
        })
        .to_return(body: { access_token: "user-access-token" }.to_json)

      response = described_class.new.exchange_code(
        code: "authorization-code",
        redirect_uri: "http://127.0.0.1:3000/auth/tiktok/callback",
        code_verifier: "tiktok-code-verifier"
      )

      expect(response.fetch("access_token")).to eq("user-access-token")
    end
  end

  describe "#refresh_token" do
    it "returns refreshed credentials from TikTok's form encoded token endpoint" do
      stub_request(:post, "https://open.tiktokapis.com/v2/oauth/token/")
        .with(body: {
          "client_key" => "tiktok-test-client",
          "client_secret" => "tiktok-test-secret",
          "grant_type" => "refresh_token",
          "refresh_token" => "old-refresh-token"
        })
        .to_return(body: { access_token: "new-access-token", refresh_token: "new-refresh-token" }.to_json)

      response = described_class.new.refresh_token(refresh_token: "old-refresh-token")

      expect(response).to eq("access_token" => "new-access-token", "refresh_token" => "new-refresh-token")
    end
  end

  describe "#profile" do
    it "returns only the authorized TikTok profile fields" do
      stub_request(:get, "https://open.tiktokapis.com/v2/user/info/")
        .with(
          query: { "fields" => "open_id,display_name" },
          headers: { "Authorization" => "Bearer user-access-token" }
        )
        .to_return(body: {
          data: { user: { open_id: "creator-1", display_name: "Nhà sáng tạo" } },
          error: { code: "ok" }
        }.to_json)

      profile = described_class.new.profile(access_token: "user-access-token")

      expect(profile).to eq("open_id" => "creator-1", "display_name" => "Nhà sáng tạo")
    end
  end

  describe "#creator_info" do
    it "returns the latest creator privacy and interaction settings" do
      stub_request(:post, "https://open.tiktokapis.com/v2/post/publish/creator_info/query/")
        .with(headers: { "Authorization" => "Bearer creator-access-token" })
        .to_return(body: {
          data: { privacy_level_options: [ "SELF_ONLY" ], comment_disabled: true },
          error: { code: "ok" }
        }.to_json)

      response = described_class.new.creator_info(access_token: "creator-access-token")

      expect(response).to eq(
        "data" => { "privacy_level_options" => [ "SELF_ONLY" ], "comment_disabled" => true },
        "error" => { "code" => "ok" }
      )
    end
  end

  describe "#init_video_publish" do
    it "starts a FILE_UPLOAD Direct Post with explicit creator consent" do
      post_info = {
        "privacy_level" => "SELF_ONLY",
        "disable_comment" => false,
        "disable_duet" => true,
        "disable_stitch" => false,
        "brand_content_toggle" => false,
        "brand_organic_toggle" => false,
        "is_aigc" => true
      }
      source_info = {
        "source" => "FILE_UPLOAD",
        "video_size" => 12,
        "chunk_size" => 12,
        "total_chunk_count" => 1
      }
      stub_request(:post, "https://open.tiktokapis.com/v2/post/publish/video/init/")
        .with(
          headers: { "Authorization" => "Bearer creator-access-token" },
          body: { post_info:, source_info: }.to_json
        )
        .to_return(body: { data: { publish_id: "publish-1", upload_url: "https://open-upload.tiktokapis.com/video?upload_token=signed" }, error: { code: "ok" } }.to_json)

      response = described_class.new.init_video_publish(
        access_token: "creator-access-token",
        post_info:,
        source_info:
      )

      expect(response).to eq(
        "data" => { "publish_id" => "publish-1", "upload_url" => "https://open-upload.tiktokapis.com/video?upload_token=signed" },
        "error" => { "code" => "ok" }
      )
    end
  end

  describe "#upload_file" do
    it "uploads chunks sequentially and checkpoints each confirmed byte offset" do
      file_size = 10_000_001
      chunked_client = described_class.new(
        configuration: described_class::CONFIGURATION.merge(upload_chunk_size_bytes: 5_000_000)
      )
      upload_url = "https://open-upload.tiktokapis.com/video?upload_token=signed"
      first_chunk_request = stub_request(:put, upload_url)
        .with(
          headers: {
            "Content-Length" => "5000000",
            "Content-Range" => "bytes 0-4999999/#{file_size}",
            "Content-Type" => "video/mp4"
          }
        )
        .to_return(status: 206)
      final_chunk_request = stub_request(:put, upload_url)
        .with(
          headers: {
            "Content-Length" => "5000001",
            "Content-Range" => "bytes 5000000-10000000/#{file_size}",
            "Content-Type" => "video/mp4"
          }
        )
        .to_return(status: 201)
      uploaded_offsets = []

      result = chunked_client.upload_file(
        upload_url:,
        file: StringIO.new("v" * file_size),
        file_size:,
        resume_offset: 0
      ) { |offset| uploaded_offsets << offset }

      expect(result).to eq("uploaded_bytes" => file_size)
      expect(uploaded_offsets).to eq([ 5_000_000, file_size ])
      expect(first_chunk_request).to have_been_requested.once
      expect(final_chunk_request).to have_been_requested.once
    end

    it "resumes upload from the stored byte offset" do
      file_size = 10_000_001
      upload_url = "https://open-upload.tiktokapis.com/video?upload_token=signed"
      upload_request = stub_request(:put, upload_url)
        .with(headers: { "Content-Range" => "bytes 5000000-10000000/#{file_size}" })
        .to_return(status: 201)
      uploaded_offsets = []

      result = described_class.new(
        configuration: described_class::CONFIGURATION.merge(upload_chunk_size_bytes: 5_000_000)
      ).upload_file(
        upload_url:,
        file: StringIO.new("v" * file_size),
        file_size:,
        resume_offset: 5_000_000
      ) { |offset| uploaded_offsets << offset }

      expect(result.fetch("uploaded_bytes")).to eq(file_size)
      expect(uploaded_offsets).to eq([ file_size ])
      expect(upload_request).to have_been_requested.once
    end

    it "returns the final byte offset after resuming an upload with four chunks" do
      file_size = 20_000_001
      upload_url = "https://open-upload.tiktokapis.com/video?upload_token=signed"
      second_chunk_request = stub_request(:put, upload_url)
        .with(headers: { "Content-Range" => "bytes 5000000-9999999/#{file_size}" })
        .to_return(status: 206)
      third_chunk_request = stub_request(:put, upload_url)
        .with(headers: { "Content-Range" => "bytes 10000000-14999999/#{file_size}" })
        .to_return(status: 206)
      final_chunk_request = stub_request(:put, upload_url)
        .with(headers: { "Content-Range" => "bytes 15000000-20000000/#{file_size}" })
        .to_return(status: 201)
      uploaded_offsets = []

      result = described_class.new(
        configuration: described_class::CONFIGURATION.merge(upload_chunk_size_bytes: 5_000_000)
      ).upload_file(
        upload_url:,
        file: StringIO.new("v" * file_size),
        file_size:,
        resume_offset: 5_000_000
      ) { |offset| uploaded_offsets << offset }

      expect(result).to eq("uploaded_bytes" => file_size)
      expect(uploaded_offsets).to eq([ 10_000_000, 15_000_000, file_size ])
      expect(second_chunk_request).to have_been_requested.once
      expect(third_chunk_request).to have_been_requested.once
      expect(final_chunk_request).to have_been_requested.once
    end

    it "raises when TikTok acknowledges the final chunk as incomplete" do
      upload_url = "https://open-upload.tiktokapis.com/video?upload_token=signed"
      stub_request(:put, upload_url).to_return(status: 206)

      expect do
        described_class.new.upload_file(
          upload_url:,
          file: StringIO.new("video"),
          file_size: 5,
          resume_offset: 0
        )
      end.to raise_error(described_class::Error, "tiktok_upload_not_confirmed")
    end

    it "rejects upload URLs outside TikTok's upload hosts before sending file bytes" do
      upload_url = "https://127.0.0.1/private?upload_token=signed"
      upload_request = stub_request(:put, upload_url).to_return(status: 201)

      expect do
        described_class.new.upload_file(
          upload_url:,
          file: StringIO.new("video bytes"),
          file_size: 11,
          resume_offset: 0
        )
      end.to raise_error(described_class::Error, "invalid_upload_url")
      expect(upload_request).not_to have_been_requested
    end
  end

  describe "#file_upload_source_info" do
    it "returns multiple chunks for a video larger than TikTok's single-chunk limit" do
      source_info = described_class.new.file_upload_source_info(file_size: 64_000_001)

      expect(source_info).to eq(
        "source" => "FILE_UPLOAD",
        "video_size" => 64_000_001,
        "chunk_size" => 32_000_000,
        "total_chunk_count" => 2
      )
    end
  end

  describe "#publish_status" do
    it "returns the final processing state for the publish ID" do
      stub_request(:post, "https://open.tiktokapis.com/v2/post/publish/status/fetch/")
        .with(
          headers: { "Authorization" => "Bearer creator-access-token" },
          body: { publish_id: "publish-1" }.to_json
        )
        .to_return(body: { data: { status: "PUBLISH_COMPLETE" }, error: { code: "ok" } }.to_json)

      response = described_class.new.publish_status(access_token: "creator-access-token", publish_id: "publish-1")

      expect(response).to eq("data" => { "status" => "PUBLISH_COMPLETE" }, "error" => { "code" => "ok" })
    end
  end

  describe "#video_query" do
    it "returns TikTok's share URL for a specific public video ID" do
      stub_request(:post, "https://open.tiktokapis.com/v2/video/query/")
        .with(
          query: { "fields" => "id,share_url" },
          headers: { "Authorization" => "Bearer creator-access-token" },
          body: { filters: { video_ids: [ "post-1" ] } }.to_json
        )
        .to_return(body: {
          data: { videos: [ { id: "post-1", share_url: "https://www.tiktok.com/@creator/video/post-1" } ] },
          error: { code: "ok" }
        }.to_json)

      video = described_class.new.video_query(access_token: "creator-access-token", video_ids: [ "post-1" ])

      expect(video).to eq("id" => "post-1", "share_url" => "https://www.tiktok.com/@creator/video/post-1")
    end

    it "returns video details when the publish status supplies a numeric int64 ID" do
      video_id = 12_345_678_901_234_567_890
      stub_request(:post, "https://open.tiktokapis.com/v2/video/query/")
        .with(
          query: { "fields" => "id,share_url" },
          headers: { "Authorization" => "Bearer creator-access-token" },
          body: { filters: { video_ids: [ video_id.to_s ] } }.to_json
        )
        .to_return(body: {
          data: { videos: [ { id: video_id.to_s, share_url: "https://www.tiktok.com/@creator/video/#{video_id}" } ] },
          error: { code: "ok" }
        }.to_json)

      video = described_class.new.video_query(access_token: "creator-access-token", video_ids: [ video_id ])

      expect(video).to eq(
        "id" => video_id.to_s,
        "share_url" => "https://www.tiktok.com/@creator/video/#{video_id}"
      )
    end
  end

  describe "provider errors" do
    it "returns a safe error code without echoing the access token or provider message" do
      stub_request(:post, "https://open.tiktokapis.com/v2/post/publish/creator_info/query/")
        .with(headers: { "Authorization" => "Bearer tiktok-access-token-secret" })
        .to_return(status: 401, body: {
          error: { code: "access_token_invalid", message: "Invalid tiktok-access-token-secret" }
        }.to_json)

      expect { described_class.new.creator_info(access_token: "tiktok-access-token-secret") }
        .to raise_error(described_class::Error, "access_token_invalid")
    end
  end

  describe "sensitive request data" do
    it "does not write an access token or signed upload URL to logs" do
      access_token = "tiktok-access-token-secret"
      upload_url = "https://open-upload.tiktokapis.com/video?upload_token=signed-upload-secret"
      log_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(log_output)
      stub_request(:put, upload_url).to_return(status: 500, body: { message: access_token }.to_json)

      expect do
        described_class.new.upload_file(
          upload_url:,
          file: StringIO.new("video"),
          file_size: 5,
          resume_offset: 0
        )
      end.to raise_error(described_class::Error)
      expect(log_output.string).not_to match(Regexp.union(access_token, upload_url))
    ensure
      Rails.logger = original_logger
    end
  end
end
