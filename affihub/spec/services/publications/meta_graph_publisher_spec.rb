require "rails_helper"

RSpec.describe Publications::MetaGraphPublisher, type: :service do
  describe "#call" do
    let(:publication) do
      create(:publication, social_destination: create(:social_destination, external_id: "page-1"))
    end
    let(:graph_api_url) do
      configuration = Meta::Client::CONFIGURATION
      "#{configuration.fetch(:graph_api_base_url)}/#{configuration.fetch(:api_version)}"
    end
    let(:page_reel_request) do
      stub_request(:post, "#{graph_api_url}/page-1/video_reels").to_return(
        { body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json },
        { body: { success: true }.to_json }
      )
    end
    let(:upload_request) do
      stub_request(:post, "https://rupload.facebook.com/upload/video-1").to_return(
        body: { success: true }.to_json
      )
    end
    let(:status_request) do
      stub_request(:get, "#{graph_api_url}/video-1").to_return(
        body: {
          status: {
            video_status: "ready",
            publishing_phase: { status: "complete" }
          },
          permalink_url: "https://facebook.com/reel/1"
        }.to_json
      )
    end
    let(:service) { described_class.new(publication_id: publication.id) }

    before do
      publication.render_version.file.attach(
        io: StringIO.new("video bytes"),
        filename: "render.mp4",
        content_type: "video/mp4"
      )
      page_reel_request
      upload_request
      status_request
    end

    it "marks the Publication published after Meta confirms the final Reel status" do
      service.call

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("video-1")
      expect(publication.permalink).to eq("https://facebook.com/reel/1")
      expect(publication.published_at).to be_present
    end

    context "when Meta has not confirmed the final Reel status" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").to_return(
          body: {
            status: {
              video_status: "ready",
              publishing_phase: { status: "in_progress" }
            }
          }.to_json
        )
      end

      it "keeps the Publication out of the published state" do
        service.call

        expect(publication.reload.status).not_to eq("published")
        expect(publication.published_at).to be_nil
        expect(publication.permalink).to be_nil
      end
    end

    context "when Meta's final status request times out" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").to_raise(Net::ReadTimeout)
      end

      it "keeps the Publication unresolved and does not retry the publish request" do
        service.call

        expect(publication.reload.status).to eq("outcome_unknown")
        expect(page_reel_request).to have_been_requested.twice
        expect(status_request).to have_been_requested.once
      end
    end
  end
end
