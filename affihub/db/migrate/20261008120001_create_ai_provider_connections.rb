class CreateAiProviderConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_provider_connections do |table|
      table.string :provider, null: false
      table.string :provider_subject, null: false
      table.string :provider_client_id, null: false
      table.string :account_email
      table.string :display_name
      table.text :access_token, null: false
      table.text :refresh_token
      table.text :id_token
      table.datetime :access_token_expires_at
      table.jsonb :scopes, null: false, default: []
      table.jsonb :available_models, null: false, default: []
      table.string :selected_model
      table.datetime :last_verified_at
      table.string :status, null: false
      table.timestamps

      table.index [ :provider, :provider_client_id, :provider_subject ], unique: true,
                  name: :index_ai_provider_connections_on_provider_client_and_subject
      table.index [ :provider, :status ]
    end
  end
end
