class CreateRenderVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :render_versions do |t|
      t.references :source_asset, null: false, foreign_key: true
      t.integer :version_number, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.jsonb :edit_config, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
