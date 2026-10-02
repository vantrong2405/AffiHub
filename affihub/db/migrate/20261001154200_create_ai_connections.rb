class CreateAIConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :access_token
      t.string :refresh_token
      t.datetime :access_token_expires_at
      t.string :status, null: false, default: "disconnected"

      t.timestamps
    end
  end
end
