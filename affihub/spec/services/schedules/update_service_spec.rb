require "rails_helper"

RSpec.describe Schedules::UpdateService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "returns a paused Schedule and skips an elapsed occurrence before jitter dispatch" do
      schedule = create(:schedule, recurrence: "daily")
      scheduled_at = 5.minutes.ago
      occurrence = create(
        :schedule_occurrence,
        schedule:,
        occurrence_key: scheduled_at.utc.iso8601(6),
        scheduled_at:,
        dispatch_at: scheduled_at + 20.minutes
      )
      service = described_class.new(video_project_id: schedule.render_version.video_project_id,
        schedule_id: schedule.id, status: "paused")

      expect(service.call).to eq(true)

      expect(schedule.reload.status).to eq("paused")
      expect(occurrence.reload.status).to eq("skipped")
      expect(schedule.next_occurrence_at > Time.current).to eq(true)
      expect(occurrence.publications.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(0)
    end

    it "returns an active recurring Schedule without publishing an occurrence missed during pause" do
      schedule = create(:schedule, recurrence: "daily", status: "paused")
      scheduled_at = 5.minutes.ago
      occurrence = create(
        :schedule_occurrence,
        schedule:,
        occurrence_key: scheduled_at.utc.iso8601(6),
        scheduled_at:,
        dispatch_at: scheduled_at + 20.minutes
      )
      service = described_class.new(video_project_id: schedule.render_version.video_project_id,
        schedule_id: schedule.id, status: "active")

      expect(service.call).to eq(true)

      expect(schedule.reload.status).to eq("active")
      expect(occurrence.reload.status).to eq("skipped")
      expect(schedule.next_occurrence_at > Time.current).to eq(true)
      expect(occurrence.publications.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count).to eq(0)
    end

    it "returns the updated local time, timezone, and recurrence on the next occurrence" do
      schedule = create(:schedule, recurrence: "daily")
      occurrence = create(:schedule_occurrence, schedule:)
      expected_at = ActiveSupport::TimeZone["America/New_York"].parse("2026-10-12 09:30")
      allow(SecureRandom).to receive(:random_number).and_return(0)
      service = described_class.new(
        video_project_id: schedule.render_version.video_project_id,
        schedule_id: schedule.id,
        scheduled_at: "2026-10-12T09:30",
        time_zone: "America/New_York",
        recurrence: "weekly",
        status: "paused"
      )

      expect(service.call).to eq(true)

      expect(schedule.reload.time_zone).to eq("America/New_York")
      expect(schedule.recurrence).to eq("weekly")
      expect(schedule.local_time).to eq("09:30:00")
      expect(schedule.next_occurrence_at).to eq(expected_at)
      expect(occurrence.reload.scheduled_at).to eq(expected_at)
      dispatch_window = expected_at + 5.minutes..expected_at + 30.minutes
      expect(dispatch_window.cover?(occurrence.dispatch_at)).to eq(true)
    end

    it "returns failure when the selected Schedule belongs to another project" do
      video_project = create(:video_project)
      schedule = create(:schedule)
      service = described_class.new(video_project_id: video_project.id, schedule_id: schedule.id, status: "paused")

      expect(service.call).to eq(false)

      expect(service.schedule).to eq(nil)
    end

    it "returns a cancelled Schedule and skips only undispatched occurrences" do
      schedule = create(:schedule, recurrence: "daily")
      scheduled_occurrence = create(:schedule_occurrence, schedule:)
      dispatched_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched",
        occurrence_key: "dispatched-#{SecureRandom.uuid}")
      service = described_class.new(video_project_id: schedule.render_version.video_project_id,
        schedule_id: schedule.id, status: "cancelled")

      expect(service.call).to eq(true)

      expect(schedule.reload.status).to eq("cancelled")
      expect(schedule.next_occurrence_at).to eq(nil)
      expect(scheduled_occurrence.reload.status).to eq("skipped")
      expect(dispatched_occurrence.reload.status).to eq("dispatched")
    end
  end
end
