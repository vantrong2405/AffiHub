class CreateSocialConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :social_connections do |table|
      table.string :provider, null: false
      table.string :external_user_id, null: false
      table.string :name, null: false
      table.text :access_token, null: false
      table.datetime :token_expires_at
      table.string :status, null: false
      table.jsonb :metadata, null: false, default: {}
      table.timestamps

      table.index [ :provider, :external_user_id ], unique: true
      table.index [ :provider, :status ]
    end

    create_table :social_destinations do |table|
      table.references :social_connection, null: false, foreign_key: true
      table.string :provider, null: false
      table.string :external_id, null: false
      table.string :name, null: false
      table.text :access_token, null: false
      table.datetime :token_expires_at
      table.string :status, null: false
      table.jsonb :metadata, null: false, default: {}
      table.timestamps

      table.index [ :social_connection_id, :external_id ], unique: true,
                  name: :index_social_destinations_on_connection_and_external_id
      table.index [ :provider, :status ]
    end
  end
end
