class CreatePublicationsAndPreflightReports < ActiveRecord::Migration[8.1]
  def change
    create_table :preflight_reports do |table|
      table.references :render_version, null: false, foreign_key: true
      table.jsonb :checked_destination_ids, null: false, default: []
      table.jsonb :destination_results, null: false, default: {}
      table.datetime :checked_at, null: false
      table.timestamps

      table.index [ :render_version_id, :checked_at ]
    end

    create_table :publications do |table|
      table.references :render_version, null: false, foreign_key: true
      table.references :social_destination, null: false, foreign_key: true
      table.string :status, null: false
      table.text :caption, null: false, default: ""
      table.datetime :scheduled_at
      table.string :schedule_occurrence_key
      table.string :platform_post_id
      table.text :permalink
      table.datetime :published_at
      table.jsonb :provider_reference, null: false, default: {}
      table.string :safe_error_code
      table.timestamps

      table.index [ :social_destination_id, :status ]
      table.index [ :render_version_id, :social_destination_id ]
      table.index :schedule_occurrence_key
    end
  end
end
