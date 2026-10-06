class CreateSourceAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :source_assets do |t|
      t.references :video_project, null: false, foreign_key: true
      t.string :source_type
      t.text :source_url
      t.jsonb :provenance, null: false, default: {}
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
