require "rails_helper"

RSpec.describe "Meta::Client", type: :service do
  describe "#exchange_code" do
    it "returns the token response from the configured Graph API version" do
      stub_request(:get, "https://graph.facebook.com/v26.0/oauth/access_token")
        .with(query: hash_including("code" => "oauth-code", "redirect_uri" => "http://localhost:3000/auth/facebook/callback"))
        .to_return(body: { access_token: "user-token", expires_in: 5_184_000 }.to_json)

      response = "Meta::Client".constantize.new.exchange_code(
        code: "oauth-code", redirect_uri: "http://localhost:3000/auth/facebook/callback"
      )

      expect(response).to eq("access_token" => "user-token", "expires_in" => 5_184_000)
    end
  end

  describe "#pages" do
    it "returns the Page list authorized for the connected profile" do
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: hash_including("access_token" => "user-token"))
        .to_return(body: { data: [ { id: "page-1", name: "Page Một", access_token: "page-token" } ] }.to_json)

      pages = "Meta::Client".constantize.new.pages(access_token: "user-token")

      expect(pages).to eq([ { "id" => "page-1", "name" => "Page Một", "access_token" => "page-token" } ])
    end
  end

  describe "#start_reel_upload" do
    it "returns the video ID and upload URL from the selected Page" do
      stub_request(:post, "https://graph.facebook.com/v26.0/page-1/video_reels")
        .with(query: hash_including("upload_phase" => "start", "access_token" => "page-token"))
        .to_return(body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json)

      response = "Meta::Client".constantize.new.start_reel_upload(page_id: "page-1", page_access_token: "page-token")

      expect(response).to eq("video_id" => "video-1", "upload_url" => "https://rupload.facebook.com/upload/video-1")
    end
  end

  describe "#upload_reel" do
    it "returns the provider upload acknowledgement for the complete file" do
      file = StringIO.new("sample mp4 bytes")
      stub_request(:post, "https://rupload.facebook.com/video-upload/v26.0/video-1")
        .with(headers: { "Authorization" => "OAuth page-token", "offset" => "0", "file_size" => "16" })
        .to_return(body: { success: true }.to_json)

      response = "Meta::Client".constantize.new.upload_reel(
        upload_url: "https://rupload.facebook.com/video-upload/v26.0/video-1",
        page_access_token: "page-token", file:, file_size: 16
      )

      expect(response).to eq("success" => true)
    end
  end

  describe "#finish_reel_upload" do
    it "returns the publish acknowledgement for the uploaded video" do
      stub_request(:post, "https://graph.facebook.com/v26.0/page-1/video_reels")
        .with(query: hash_including("upload_phase" => "finish", "video_id" => "video-1", "video_state" => "PUBLISHED"))
        .to_return(body: { success: true }.to_json)

      response = "Meta::Client".constantize.new.finish_reel_upload(
        page_id: "page-1", page_access_token: "page-token", video_id: "video-1", caption: "Caption"
      )

      expect(response).to eq("success" => true)
    end
  end

  describe "#reel_status" do
    it "returns the confirmed final status and permalink fields" do
      stub_request(:get, "https://graph.facebook.com/v26.0/video-1")
        .with(query: hash_including("fields" => "status,permalink_url"))
        .to_return(body: { status: { video_status: "PUBLISHED" }, permalink_url: "https://facebook.com/reel/1" }.to_json)

      status = "Meta::Client".constantize.new.reel_status(video_id: "video-1", page_access_token: "page-token")

      expect(status).to eq("status" => { "video_status" => "PUBLISHED" }, "permalink_url" => "https://facebook.com/reel/1")
    end
  end

  describe "provider errors" do
    it "returns a safe error code without echoing the token or provider message" do
      stub_request(:get, "https://graph.facebook.com/v26.0/me/accounts")
        .with(query: hash_including("access_token" => "user-token-secret"))
        .to_return(status: 400, body: { error: { code: 190, message: "Invalid user-token-secret" } }.to_json)

      expect { "Meta::Client".constantize.new.pages(access_token: "user-token-secret") }
        .to raise_error("Meta::Client::Error".constantize, "graph_api_190")
    end
  end
end
