class CreateSocialDestinations < ActiveRecord::Migration[8.1]
  def change
    create_table :social_destinations do |t|
      t.references :social_connection, null: false, foreign_key: true
      t.string :destination_type
      t.string :page_id
      t.string :name
      t.string :page_access_token

      t.timestamps
    end

    add_index :social_destinations, [ :social_connection_id, :page_id ], unique: true
  end
end
