class CreatePublicationQuotaReservations < ActiveRecord::Migration[8.1]
  def change
    create_table :publication_quota_reservations do |t|
      t.references :publication, null: false, foreign_key: true, index: { unique: true }
      t.references :social_destination, null: false, foreign_key: true
      t.datetime :reserved_at, null: false

      t.timestamps
    end

    add_index :publication_quota_reservations, [ :social_destination_id, :reserved_at ],
      name: "index_publication_quota_reservations_on_destination_and_time"
  end
end
