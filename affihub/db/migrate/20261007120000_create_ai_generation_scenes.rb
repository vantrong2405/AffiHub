class CreateAiGenerationScenes < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_generation_scenes do |table|
      table.references :ai_generation, null: false, foreign_key: true
      table.integer :scene_index, null: false
      table.string :status, null: false
      table.text :prompt_snapshot
      table.text :narration_snapshot, null: false
      table.string :voice_name, null: false
      table.jsonb :estimate_snapshot, null: false, default: {}
      table.jsonb :consent_snapshot, null: false, default: {}
      table.jsonb :actual_costs, null: false, default: {}
      table.string :safe_error_code
      table.timestamps

      table.index [ :ai_generation_id, :scene_index ], unique: true
      table.index [ :ai_generation_id, :status ]
    end
  end
end
