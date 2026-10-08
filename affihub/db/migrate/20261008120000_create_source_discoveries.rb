class CreateSourceDiscoveries < ActiveRecord::Migration[8.1]
  def change
    create_table :source_discoveries do |table|
      table.references :video_project, null: false, foreign_key: true
      table.string :search_type, null: false
      table.string :search_query
      table.string :region_code, null: false
      table.string :video_category_id
      table.datetime :searched_at, null: false
      table.timestamps
    end
    add_index :source_discoveries, [ :video_project_id, :searched_at ]

    create_table :source_discovery_results do |table|
      table.references :source_discovery, null: false, foreign_key: { on_delete: :cascade }
      table.references :youtube_discovery_metadata, null: false, foreign_key: { on_delete: :cascade }
      table.integer :position, null: false
      table.timestamps
    end
    add_index :source_discovery_results, [ :source_discovery_id, :position ], unique: true
    add_index :source_discovery_results, [ :source_discovery_id, :youtube_discovery_metadata_id ],
      unique: true, name: "index_source_discovery_results_on_search_and_metadata"
  end
end
