class CreateAffiliateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :affiliate_connections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider
      t.string :api_key

      t.timestamps
    end
  end
end
