class CreateAiGenerations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_generations do |table|
      table.references :video_project, null: false, foreign_key: true
      table.references :source_asset, foreign_key: true
      table.string :status, null: false
      table.string :correlation_id, null: false
      table.string :task_id
      table.integer :provider_state
      table.string :safe_error_code
      table.jsonb :input_snapshot, null: false, default: {}
      table.jsonb :estimate_snapshot, null: false, default: {}
      table.jsonb :consent_snapshot, null: false, default: {}
      table.jsonb :actual_costs, null: false, default: {}
      table.timestamps

      table.index :correlation_id, unique: true
      table.index :task_id, unique: true, where: "task_id IS NOT NULL"
    end
  end
end
