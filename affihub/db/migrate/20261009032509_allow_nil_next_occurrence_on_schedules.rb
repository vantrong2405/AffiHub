class AllowNilNextOccurrenceOnSchedules < ActiveRecord::Migration[8.1]
  def change
    change_column_null :schedules, :next_occurrence_at, true
  end
end
