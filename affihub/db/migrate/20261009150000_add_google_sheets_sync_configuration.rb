class AddGoogleSheetsSyncConfiguration < ActiveRecord::Migration[8.1]
  def change
    add_column :google_connections, :spreadsheet_id, :string
    add_column :google_connections, :worksheet_title, :string

    create_table :sheet_syncs do |table|
      table.references :google_connection, null: false, foreign_key: true
      table.references :render_version, null: false, foreign_key: true
      table.references :social_destination, null: false, foreign_key: true
      table.string :sheet_row_key, null: false
      table.integer :row_number
      table.string :status, null: false
      table.string :safe_error_code
      table.datetime :last_synced_at
      table.timestamps

      table.index [ :google_connection_id, :render_version_id, :social_destination_id ],
                  unique: true, name: :index_sheet_syncs_on_connection_render_destination
      table.index [ :status, :updated_at ], name: :index_sheet_syncs_on_status_and_updated_at
      table.index :sheet_row_key
    end
  end
end
