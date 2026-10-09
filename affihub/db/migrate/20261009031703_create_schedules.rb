class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.references :render_version, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.string :recurrence, null: false, default: "once"
      t.string :time_zone, null: false
      t.string :local_time, null: false
      t.datetime :next_occurrence_at

      t.timestamps
    end

    add_index :schedules, [ :status, :next_occurrence_at ]

    create_table :schedule_destinations do |t|
      t.references :schedule, null: false, foreign_key: true
      t.references :social_destination, null: false, foreign_key: true
      t.text :caption, null: false, default: ""
      t.jsonb :consent_snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :schedule_destinations, [ :schedule_id, :social_destination_id ],
      unique: true, name: "index_schedule_destinations_on_schedule_and_destination"

    create_table :schedule_occurrences do |t|
      t.references :schedule, null: false, foreign_key: true
      t.references :preflight_report, foreign_key: true
      t.string :occurrence_key, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :dispatch_at, null: false
      t.string :status, null: false, default: "scheduled"
      t.datetime :processed_at
      t.string :safe_error_code

      t.timestamps
    end

    add_index :schedule_occurrences, [ :schedule_id, :occurrence_key ],
      unique: true, name: "index_schedule_occurrences_on_schedule_and_key"
    add_index :schedule_occurrences, [ :status, :dispatch_at ]

    add_reference :publications, :schedule_occurrence, foreign_key: true
    add_index :publications, [ :schedule_occurrence_id, :social_destination_id ],
      unique: true, name: "index_publications_on_occurrence_and_destination"
  end
end
