require "rails_helper"

RSpec.describe ScheduleOccurrence, type: :model do
  describe "validations" do
    it "returns invalid when a schedule repeats an occurrence key" do
      schedule = create(:schedule)
      create(:schedule_occurrence, schedule:, occurrence_key: "2026-10-10T09:00:00.000000Z")
      duplicate = build(:schedule_occurrence, schedule:, occurrence_key: "2026-10-10T09:00:00.000000Z")

      expect(duplicate.valid?).to eq(false)
      expect(duplicate.errors.attribute_names).to eq([ :occurrence_key ])
    end

    it "returns invalid when dispatch begins before the minimum jitter" do
      scheduled_at = Time.current
      occurrence = build(
        :schedule_occurrence,
        scheduled_at:,
        dispatch_at: scheduled_at + 4.minutes
      )

      expect(occurrence.valid?).to eq(false)
      expect(occurrence.errors.attribute_names).to eq([ :dispatch_at ])
    end

    it "returns invalid when dispatch begins after the maximum jitter" do
      scheduled_at = Time.current
      occurrence = build(
        :schedule_occurrence,
        scheduled_at:,
        dispatch_at: scheduled_at + 31.minutes
      )

      expect(occurrence.valid?).to eq(false)
      expect(occurrence.errors.attribute_names).to eq([ :dispatch_at ])
    end
  end
end
