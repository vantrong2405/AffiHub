require "rails_helper"

RSpec.describe Schedules::ShowService, type: :service do
  describe "#call" do
    it "returns the schedule occurrences and exact destination quota availability" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      schedule = create(:schedule, render_version:)
      social_destination = create(:social_destination)
      create(:schedule_destination, schedule:, social_destination:)
      oldest_reservation = create(:publication_quota_reservation, social_destination:, reserved_at: 23.hours.ago)
      create_list(:publication_quota_reservation, 4, social_destination:, reserved_at: 10.hours.ago)
      occurrence = create(:schedule_occurrence, schedule:, status: "missed")
      service = described_class.new(video_project_id: video_project.id, schedule_id: schedule.id)

      expect(service.call).to eq(true)

      expect(service.schedule).to eq(schedule)
      expect(service.occurrences.map(&:id)).to eq([ occurrence.id ])
      expect(service.quota_summary.map do |entry|
        entry.slice(:social_destination_id, :used, :limit, :next_available_at)
      end).to eq([
        {
          social_destination_id: social_destination.id,
          used: 5,
          limit: 5,
          next_available_at: oldest_reservation.reserved_at + 24.hours
        }
      ])
    end
  end
end
