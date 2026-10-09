require "rails_helper"

RSpec.describe "Drive exports", type: :request do
  describe "POST /video_projects/:video_project_id/drive_exports" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:video_project) { create(:video_project) }
    let(:render_version) do
      render_version = create(:render_version, video_project:, status: "ready")
      File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) do |file|
        render_version.file.attach(io: file, filename: "render.mp4", content_type: "video/mp4")
      end
      render_version
    end
    let(:google_connection) { create(:google_connection, integration: "drive", status: "connected") }

    it "redirects to the created Drive export and persists one queued job" do
      post video_project_drive_exports_path(video_project), params: {
        render_version_id: render_version.id,
        google_connection_id: google_connection.id
      }

      drive_export = DriveExport.find_by!(render_version:, google_connection:)

      expect(response).to redirect_to(video_project_drive_export_path(video_project, drive_export))
      expect(drive_export.status).to eq("queued")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end

    it "rejects a render version from a different project without creating an export" do
      other_project = create(:video_project)
      other_render_version = create(:render_version, video_project: other_project, status: "ready")
      google_connection

      post video_project_drive_exports_path(video_project), params: {
        render_version_id: other_render_version.id,
        google_connection_id: google_connection.id
      }

      expect(response).to redirect_to(video_project_path(video_project))
      expect(DriveExport.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end
  end

  describe "GET /video_projects/:video_project_id/drive_exports" do
    it "returns Drive export statuses for the selected project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      google_connection = create(:google_connection, integration: "drive")
      create(:drive_export, render_version:, google_connection:)

      get video_project_drive_exports_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/drive_exports/:id" do
    it "returns a single export status page" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      drive_export = create(:drive_export, render_version:)

      get video_project_drive_export_path(video_project, drive_export)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /video_projects/:video_project_id/drive_exports/:id" do
    it "persists a confirmed Drive upload from its OutcomeUnknown page" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      drive_export = create(:drive_export, render_version:, status: "outcome_unknown")
      create(
        :workflow_run,
        workflowable: drive_export,
        operation: "drive_export_upload",
        stage: "upload",
        status: "outcome_unknown"
      )

      patch video_project_drive_export_path(video_project, drive_export), params: {
        decision: "occurred",
        evidence: "Đã kiểm tra file trong Drive cá nhân.",
        actor_reference: "Chủ tài khoản",
        provider_reference: "https://drive.google.com/file/d/drive-file-123/view"
      }

      expect(response).to redirect_to(video_project_drive_export_path(video_project, drive_export))
      expect(drive_export.reload.status).to eq("manual_outcome_confirmed")
      expect(drive_export.drive_file_id).to eq("drive-file-123")
    end
  end
end
