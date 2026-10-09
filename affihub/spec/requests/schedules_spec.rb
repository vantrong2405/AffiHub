require "rails_helper"

RSpec.describe "Schedule pages", type: :request do
  describe "GET /video_projects/:video_project_id/schedules" do
    it "returns the project's schedule list" do
      video_project = create(:video_project)

      get video_project_schedules_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/schedules/new" do
    it "returns the schedule form for a selected preflight report" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready")
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )

      get new_video_project_schedule_path(video_project, preflight_report_id: preflight_report.id)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /video_projects/:video_project_id/schedules" do
    it "creates a schedule with its destination snapshot and selected timezone" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready")
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )
      scheduled_at = 2.days.from_now.in_time_zone("Asia/Ho_Chi_Minh").strftime("%Y-%m-%dT%H:%M")

      expect do
        post video_project_schedules_path(video_project), params: {
          schedule: {
            render_version_id: render_version.id,
            preflight_report_id: preflight_report.id,
            scheduled_at:,
            time_zone: "Asia/Ho_Chi_Minh",
            recurrence: "daily",
            destination_ids: [ social_destination.id ],
            destination_captions: { social_destination.id.to_s => "Video mới" }
          }
        }
      end.to change(Schedule, :count).by(1)
        .and change(ScheduleOccurrence, :count).by(1)

      schedule = Schedule.order(:id).last

      expect(response).to redirect_to(video_project_schedule_path(video_project, schedule))
      expect(schedule.time_zone).to eq("Asia/Ho_Chi_Minh")
      expect(schedule.schedule_destinations.sole.caption).to eq("Video mới")
    end
  end

  describe "PATCH /video_projects/:video_project_id/schedules/:id" do
    it "pauses the selected Schedule" do
      schedule = create(:schedule)
      video_project = schedule.render_version.video_project

      patch video_project_schedule_path(video_project, schedule), params: { schedule: { status: "paused" } }

      expect(response).to redirect_to(video_project_schedule_path(video_project, schedule))
      expect(schedule.reload.status).to eq("paused")
    end
  end

  describe "DELETE /video_projects/:video_project_id/schedules/:id" do
    it "cancels the Schedule and clears its next occurrence" do
      schedule = create(:schedule)
      video_project = schedule.render_version.video_project

      delete video_project_schedule_path(video_project, schedule)

      expect(response).to redirect_to(video_project_schedules_path(video_project))
      expect(schedule.reload.status).to eq("cancelled")
      expect(schedule.next_occurrence_at).to eq(nil)
    end
  end
end
