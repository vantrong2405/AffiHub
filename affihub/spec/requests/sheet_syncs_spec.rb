require "rails_helper"

RSpec.describe "Sheet syncs", type: :request do
  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  describe "GET /video_projects/:video_project_id/sheet_syncs" do
    it "returns sync status and selected render choices for one project" do
      video_project = create(:video_project)

      get video_project_sheet_syncs_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/sheet_syncs/:id" do
    it "returns the sync status for the selected row" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      google_connection = create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-1234567890",
        worksheet_title: "Lịch đăng"
      )
      sheet_sync = create(:sheet_sync, google_connection:, render_version:, social_destination:)

      get video_project_sheet_sync_path(video_project, sheet_sync)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /video_projects/:video_project_id/sheet_syncs" do
    it "queues only the selected render and persists its current destination row" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      create(:publication, render_version:, social_destination:)
      google_connection = create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-1234567890",
        worksheet_title: "Lịch đăng"
      )

      post video_project_sheet_syncs_path(video_project), params: {
        google_connection_id: google_connection.id,
        render_version_ids: [ render_version.id ]
      }

      sheet_sync = SheetSync.find_by!(google_connection:, render_version:, social_destination:)
      expect(response).to redirect_to(video_project_sheet_syncs_path(video_project))
      expect(sheet_sync.status).to eq("queued")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end
  end
end
