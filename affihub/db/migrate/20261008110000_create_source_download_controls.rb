class CreateSourceDownloadControls < ActiveRecord::Migration[8.1]
  def change
    add_column :source_assets, :download_error_code, :string
    add_column :source_assets, :download_error, :text

    create_table :source_download_gates do |table|
      table.string :key, null: false
      table.timestamps
    end
    add_index :source_download_gates, :key, unique: true

    create_table :source_download_slots do |table|
      table.datetime :started_at, null: false
      table.timestamps
    end
    add_index :source_download_slots, :started_at
  end
end
