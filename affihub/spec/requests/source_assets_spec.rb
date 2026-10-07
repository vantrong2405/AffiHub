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
