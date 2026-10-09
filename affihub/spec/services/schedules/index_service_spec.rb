require "rails_helper"

RSpec.describe Schedules::IndexService, type: :service do
  describe "#call" do
    it "returns project schedules ordered by their next occurrence" do
      video_project = create(:video_project)
      earlier_schedule = create(
        :schedule,
        render_version: create(:render_version, video_project:),
        next_occurrence_at: 1.day.from_now
      )
      later_schedule = create(
        :schedule,
        render_version: create(:render_version, video_project:),
        next_occurrence_at: 2.days.from_now
      )
      create(:schedule)
      service = described_class.new(video_project_id: video_project.id)

      expect(service.call).to eq(true)

      expect(service.schedules.map(&:id)).to eq([ earlier_schedule.id, later_schedule.id ])
    end
  end
end
