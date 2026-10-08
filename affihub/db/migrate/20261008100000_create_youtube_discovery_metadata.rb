class CreateYoutubeDiscoveryMetadata < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_discovery_metadata do |table|
      table.string :video_id, null: false
      table.string :title, null: false
      table.string :channel_title, null: false
      table.text :thumbnail_url, null: false
      table.text :attribution_url, null: false
      table.string :discovery_type, null: false
      table.string :search_query
      table.string :region_code
      table.string :video_category_id
      table.datetime :fetched_at, null: false
      table.timestamps
    end

    add_index :youtube_discovery_metadata, :video_id, unique: true
    add_index :youtube_discovery_metadata, :fetched_at
  end
end
