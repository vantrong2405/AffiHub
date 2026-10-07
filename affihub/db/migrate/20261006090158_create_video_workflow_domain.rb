class CreateVideoWorkflowDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :video_projects do |table|
      table.string :name, null: false
      table.string :status, null: false
      table.timestamps
    end

    create_table :source_assets do |table|
      table.references :video_project, null: false, foreign_key: true
      table.string :source_type
      table.text :source_url
      table.jsonb :provenance, null: false, default: {}
      table.string :status, null: false
      table.timestamps
    end

    create_table :render_versions do |table|
      table.references :video_project, null: false, foreign_key: true
      table.references :source_asset, null: false, foreign_key: true
      table.integer :version_number, null: false, default: 1
      table.string :status, null: false
      table.jsonb :edit_config, null: false, default: {}
      table.jsonb :metadata, null: false, default: {}
      table.timestamps
    end
  end
end
