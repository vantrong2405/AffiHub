class AddSourceAssetInspectionMetadata < ActiveRecord::Migration[8.1]
  def change
    add_column :source_assets, :media_metadata, :jsonb, null: false, default: {}
    add_column :source_assets, :inspection_error, :text
  end
end
