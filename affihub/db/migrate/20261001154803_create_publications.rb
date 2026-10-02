class CreatePublications < ActiveRecord::Migration[8.1]
  def change
    create_table :publications do |t|
      t.references :content, null: false, foreign_key: true
      t.references :social_destination, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.datetime :scheduled_at
      t.string :provider_post_id
      t.string :published_url
      t.datetime :published_at
      t.string :error_code
      t.text :error_message
      t.integer :attempt_count, null: false, default: 0
      t.datetime :last_attempt_at
      t.text :provider_metadata

      t.timestamps
    end
  end
end
