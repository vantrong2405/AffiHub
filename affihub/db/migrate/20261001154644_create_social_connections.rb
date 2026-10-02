class CreateSocialConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :social_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider
      t.string :access_token

      t.timestamps
    end

    add_index :social_connections, [ :user_id, :provider ], unique: true
  end
end
