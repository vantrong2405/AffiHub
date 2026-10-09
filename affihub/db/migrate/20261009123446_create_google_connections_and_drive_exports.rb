class CreateGoogleConnectionsAndDriveExports < ActiveRecord::Migration[8.1]
  def change
    create_table :google_connections do |table|
      table.string :integration, null: false
      table.string :google_account_id, null: false
      table.string :email, null: false
      table.text :access_token, null: false
      table.text :refresh_token
      table.datetime :access_token_expires_at
      table.jsonb :scopes, null: false, default: []
      table.string :status, null: false
      table.string :safe_error_code
      table.string :drive_parent_folder_id
      table.timestamps

      table.index [ :integration, :google_account_id ], unique: true,
                  name: :index_google_connections_on_integration_and_account
      table.index [ :integration, :status ], name: :index_google_connections_on_integration_and_status
    end

    create_table :drive_exports do |table|
      table.references :google_connection, null: false, foreign_key: true
      table.references :render_version, null: false, foreign_key: true
      table.string :status, null: false
      table.string :folder_key, null: false
      table.string :file_key, null: false
      table.string :drive_folder_id
      table.string :drive_folder_url
      table.string :drive_file_id
      table.string :drive_url
      table.text :upload_session_uri
      table.bigint :upload_offset, null: false, default: 0
      table.string :safe_error_code
      table.timestamps

      table.index [ :render_version_id, :google_connection_id ], unique: true,
                  name: :index_drive_exports_on_render_and_connection
      table.index :file_key, unique: true
      table.index :folder_key
      table.index [ :status, :updated_at ], name: :index_drive_exports_on_status_and_updated_at
    end
  end
end
