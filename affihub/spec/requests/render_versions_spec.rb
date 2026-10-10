require "rails_helper"

RSpec.describe "Render version pages", type: :request do
  describe "GET /video_projects/:video_project_id/render_versions" do
    it "returns render versions from the selected project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "ready")
      create(:render_version, video_project:, source_asset:)

      get video_project_render_versions_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/render_versions/new" do
    it "returns the editor for a selected source in the project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "ready")

      get new_video_project_render_version_path(video_project, source_asset_id: source_asset.id)

      expect(response).to have_http_status(:ok)
    end

    it "returns not found when the selected source belongs to another project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, status: "ready")

      get new_video_project_render_version_path(video_project, source_asset_id: source_asset.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /video_projects/:video_project_id/render_versions" do
    it "creates and queues a render version for the selected source" do
      video_project = create(:video_project)
      source_asset = create(
        :source_asset,
        video_project:,
        status: "ready",
        media_metadata: { "duration_seconds" => 6.0, "width" => 32, "height" => 32, "has_audio" => true }
      )
      render_version_params = {
        source_asset_id: source_asset.id,
        segments: [ { start_seconds: "0", end_seconds: "1", speed: "1", audio_mode: "keep", audio_volume: "1" } ],
        canvas: { mode: "fit", background: { type: "blur" } },
        filters: { brightness: "0", contrast: "1" },
        overlays: [],
        delogo_regions: []
      }

      expect do
        post video_project_render_versions_path(video_project), params: { render_version: render_version_params }
      end.to have_enqueued_job(RenderVersions::RenderJob)

      expect(response).to redirect_to(video_project_render_version_path(video_project, RenderVersion.last))
      expect(RenderVersion.last.source_asset).to eq(source_asset)
    end
  end

  describe "GET /video_projects/:video_project_id/render_versions/:id" do
    it "returns the render preview and comparison page" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      render_version.file.attach(
        io: StringIO.new("render preview bytes"),
        filename: "render-preview.mp4",
        content_type: "video/mp4"
      )

      get video_project_render_version_path(video_project, render_version)

      expect(response).to have_http_status(:ok)
    end

    it "returns frame comparison data for a valid timecode" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready", metadata: { "duration_seconds" => 1.0 })
      render_version.source_asset.update!(media_metadata: { "duration_seconds" => 6.0, "width" => 32, "height" => 32 })
      render_version.source_asset.file.attach(io: StringIO.new("source bytes"), filename: "source.mp4", content_type: "video/mp4")
      render_version.file.attach(io: StringIO.new("render bytes"), filename: "render.mp4", content_type: "video/mp4")
      comparison_service = RenderVersions::CompareFramesService.new(
        render_version_id: render_version.id,
        timecodes: [ 1.25 ]
      )
      allow(RenderVersions::CompareFramesService).to receive(:new).and_return(comparison_service)
      allow(comparison_service).to receive(:call).and_return(true)
      allow(comparison_service).to receive(:frames).and_return([
        { timestamp_seconds: 1.25, source_frame: "data:image/jpeg;base64,c291cmNl", render_frame: "data:image/jpeg;base64,cmVuZGVy" }
      ])

      get video_project_render_version_path(video_project, render_version), params: { timecode: "1.25" }

      expect(response).to have_http_status(:ok)
    end

    it "returns an unprocessable response for a timecode outside the video duration" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready", metadata: { "duration_seconds" => 1.0 })
      render_version.source_asset.update!(media_metadata: { "duration_seconds" => 6.0, "width" => 32, "height" => 32 })
      comparison_service = RenderVersions::CompareFramesService.new(
        render_version_id: render_version.id,
        timecodes: [ 99.0 ]
      )
      comparison_service.errors.add(:base, "Timecode phải nằm trong thời lượng của cả source và render.")
      expect(RenderVersions::CompareFramesService).to receive(:new)
        .with(render_version_id: render_version.id, timecodes: [ 99.0 ])
        .and_return(comparison_service)
      allow(comparison_service).to receive(:call).and_return(false)

      get video_project_render_version_path(video_project, render_version), params: { timecode: "99" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns not found when the render version belongs to another project" do
      video_project = create(:video_project)
      render_version = create(:render_version)

      get video_project_render_version_path(video_project, render_version)

      expect(response).to have_http_status(:not_found)
    end
  end
end
