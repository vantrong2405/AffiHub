require "rails_helper"

RSpec.describe "Publications::MetaGraphPublisher", type: :service do
  describe "#call" do
    it "returns Published only after Facebook confirms the final Reel status" do
      publication = create(:publication, social_destination: create(:social_destination, external_id: "page-1"))
      publication.render_version.file.attach(io: StringIO.new("video bytes"), filename: "render.mp4", content_type: "video/mp4")
      stub_request(:post, %r{graph.facebook.com/v26.0/page-1/video_reels}).to_return(
        { body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json },
        { body: { success: true }.to_json }
      )
      stub_request(:post, "https://rupload.facebook.com/upload/video-1").to_return(body: { success: true }.to_json)
      stub_request(:get, %r{graph.facebook.com/v26.0/video-1}).to_return(body: { status: { video_status: "PUBLISHED" }, permalink_url: "https://facebook.com/reel/1" }.to_json)
      service = "Publications::MetaGraphPublisher".constantize.new(publication_id: publication.id)

      service.call

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("video-1")
      expect(publication.permalink).to eq("https://facebook.com/reel/1")
      expect(publication.published_at).to be_present
    end
  end
end
