require "rails_helper"

RSpec.describe "Source asset imports", type: :request do
  describe "GET /video_projects/:video_project_id/source_assets" do
    it "returns the source list for the project" do
      video_project = create(:video_project)
      create(:source_asset, video_project:)

      get video_project_source_assets_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/source_assets/new" do
    it "returns the local upload form for the project" do
      video_project = create(:video_project)

      get new_video_project_source_asset_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /video_projects/:video_project_id/source_assets" do
    it "returns the created source page and queues inspection after a local upload" do
      video_project = create(:video_project)
      file = fixture_file_upload("local_source.mp4", "video/mp4")

      expect do
        post video_project_source_assets_path(video_project),
             params: { source_asset: { file: } }
      end.to have_enqueued_job(SourceAssets::InspectJob)

      expect(response).to redirect_to(video_project_source_asset_path(video_project, SourceAsset.last))
      expect(SourceAsset.last.file).to be_attached
    end

    it "creates a URL source after the user confirms the rights notice" do
      video_project = create(:video_project)
      allow(Resolv).to receive(:getaddresses).with("youtu.be").and_return([ "142.250.72.238" ])

      expect do
        post video_project_source_assets_path(video_project),
             params: { source_asset: { url: "https://youtu.be/video-123", rights_confirmed: "1" } }
      end.to change(SourceAsset, :count).by(1)

      expect(response).to redirect_to(video_project_source_asset_path(video_project, SourceAsset.last))
      expect(SourceAsset.last).to have_attributes(source_type: "url_download", source_url: "https://youtu.be/video-123")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
        .to include(SourceAssets::DownloadJob)
    end

    it "rejects URL imports without the rights confirmation" do
      video_project = create(:video_project)

      expect do
        post video_project_source_assets_path(video_project),
             params: { source_asset: { url: "https://youtu.be/video-123", rights_confirmed: "0" } }
      end.not_to change(SourceAsset, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it "creates a YouTube source only from a result in the selected project discovery" do
      video_project = create(:video_project)
      discovery = create(:source_discovery, video_project:)
      metadata = create(:youtube_discovery_metadata, video_id: "selected-video")
      create(:source_discovery_result, source_discovery: discovery, youtube_discovery_metadata: metadata)
      allow(Resolv).to receive(:getaddresses).with("www.youtube.com").and_return([ "142.250.72.238" ])

      expect do
        post video_project_source_assets_path(video_project),
             params: {
               source_asset: {
                 source_discovery_id: discovery.id,
                 youtube_discovery_metadata_id: metadata.id,
                 rights_confirmed: "1"
               }
             }
      end.to change(SourceAsset, :count).by(1)

      expect(response).to redirect_to(video_project_source_asset_path(video_project, SourceAsset.last))
      expect(SourceAsset.last.provenance).to include("video_id" => "selected-video")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
        .to include(SourceAssets::DownloadJob)
    end

    it "rejects a YouTube metadata row outside the selected discovery" do
      video_project = create(:video_project)
      discovery = create(:source_discovery, video_project:)
      metadata = create(:youtube_discovery_metadata)
      allow(Resolv).to receive(:getaddresses).with("www.youtube.com").and_return([ "142.250.72.238" ])

      expect do
        post video_project_source_assets_path(video_project),
             params: {
               source_asset: {
                 source_discovery_id: discovery.id,
                 youtube_discovery_metadata_id: metadata.id,
                 rights_confirmed: "1"
               }
             }
      end.not_to change(SourceAsset, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end
  end

  describe "GET /video_projects/:video_project_id/source_assets/:id" do
    it "returns the source status page" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "processing")

      get video_project_source_asset_path(video_project, source_asset)

      expect(response).to have_http_status(:ok)
    end

    it "returns not found for a source owned by another project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset)

      get video_project_source_asset_path(video_project, source_asset)

      expect(response).to have_http_status(:not_found)
    end
  end
end
