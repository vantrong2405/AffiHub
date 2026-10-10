require "rails_helper"

RSpec.describe Schedule, type: :model do
  describe "validations" do
    it "returns valid for a supported recurrence and timezone" do
      schedule = build(:schedule)

      expect(schedule.valid?).to eq(true)
    end

    it "returns invalid for an unsupported recurrence" do
      schedule = build(:schedule, recurrence: "monthly")

      expect(schedule.valid?).to eq(false)
      expect(schedule.errors.attribute_names).to eq([ :recurrence ])
    end

    it "returns invalid for an unsupported timezone" do
      schedule = build(:schedule, time_zone: "Mars/Olympus_Mons")

      expect(schedule.valid?).to eq(false)
      expect(schedule.errors.attribute_names).to eq([ :time_zone ])
    end
  end
end
