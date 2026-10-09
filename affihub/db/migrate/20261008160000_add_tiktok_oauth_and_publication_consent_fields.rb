class AddTikTokOauthAndPublicationConsentFields < ActiveRecord::Migration[8.1]
  def change
    add_column :social_connections, :refresh_token, :text
    add_column :social_connections, :refresh_token_expires_at, :datetime
    add_column :social_connections, :scopes, :jsonb, default: [], null: false
    add_column :publications, :consent_snapshot, :jsonb, default: {}, null: false
  end
end
