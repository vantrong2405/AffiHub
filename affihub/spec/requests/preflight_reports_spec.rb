require "rails_helper"

RSpec.describe "Preflight report pages", type: :request do
  describe "POST /video_projects/:video_project_id/preflight_reports" do
    it "returns a report page and persists the selected render scope" do
      video_project = create(:video_project)
      source_metadata = {
        "duration_seconds" => 2.0,
        "width" => 1080,
        "height" => 1920,
        "frame_rate" => 30,
        "video_codec" => "h264",
        "audio_codec" => "aac",
        "has_audio" => true
      }
      source_asset = create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata)
      render_version = create(
        :render_version,
        video_project:,
        source_asset:,
        status: "ready",
        edit_config: {
          "schema_version" => 1,
          "segments" => [ { "start_seconds" => 0.0, "end_seconds" => 2.0, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 1.0 } ],
          "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
          "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
          "overlays" => [],
          "delogo_regions" => []
        },
        metadata: source_metadata
      )
      media_bytes = File.binread(Rails.root.join("spec/fixtures/files/edit_source.mp4"))
      source_asset.file.attach(io: StringIO.new(media_bytes), filename: "source.mp4", content_type: "video/mp4")
      render_version.file.attach(io: StringIO.new(media_bytes), filename: "render.mp4", content_type: "video/mp4")

      post video_project_preflight_reports_path(video_project), params: {
        preflight_report: {
          render_version_id: render_version.id,
          social_destination_ids: []
        }
      }

      expect(response.status).to eq(302)
      expect(flash[:alert]).to eq(nil)
      preflight_report = PreflightReport.find_by!(render_version:)
      expect(response.location).to eq(video_project_preflight_report_url(video_project, preflight_report))
      expect(response.location).to eq(video_project_preflight_report_url(video_project, preflight_report))
      expect(preflight_report.checked_destination_ids).to eq([])
      expect(preflight_report.destination_results.dig("project", "checks", "publish_readiness", "status")).to eq("Cảnh báo")
    end

    it "returns not found and persists no report for a render from another project" do
      video_project = create(:video_project)
      render_version = create(:render_version)

      post video_project_preflight_reports_path(video_project), params: {
        preflight_report: {
          render_version_id: render_version.id,
          social_destination_ids: []
        }
      }

      expect(response.status).to eq(404)
      expect(PreflightReport.count).to eq(0)
    end
  end

  describe "GET /video_projects/:video_project_id/preflight_reports/:id" do
    it "returns the saved report page for its project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready", metadata: { "duration_seconds" => 1.0 })
      preflight_report = create(:preflight_report, render_version:)
      frame_service = instance_double(
        RenderVersions::CompareFramesService,
        call: true,
        success?: true,
        frames: []
      )
      allow(RenderVersions::CompareFramesService).to receive(:new).and_return(frame_service)

      get video_project_preflight_report_path(video_project, preflight_report)

      expect(response.status).to eq(200)
    end

    it "returns not found when the report belongs to another project" do
      video_project = create(:video_project)
      preflight_report = create(:preflight_report)

      get video_project_preflight_report_path(video_project, preflight_report)

      expect(response.status).to eq(404)
    end

    it "returns not found when the destination filter is outside the saved report scope" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      checked_destination = create(:social_destination)
      unchecked_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ checked_destination.id ],
        destination_results: {
          "project" => { "status" => "ready", "checks" => {} },
          checked_destination.id.to_s => { "status" => "ready", "checks" => {} }
        }
      )

      get video_project_preflight_report_path(video_project, preflight_report), params: {
        destination_id: unchecked_destination.id
      }

      expect(response.status).to eq(404)
    end
  end
end
