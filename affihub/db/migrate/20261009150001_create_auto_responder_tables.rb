class CreateAutoResponderTables < ActiveRecord::Migration[8.1]
  def change
    create_table :auto_reply_rules do |t|
      t.references :social_destination, null: false, foreign_key: true
      t.string :rule_type, null: false
      t.string :keyword
      t.text :reply_text, null: false
      t.boolean :enabled, null: false
      t.timestamps
    end

    add_index :auto_reply_rules, :social_destination_id,
      unique: true,
      where: "rule_type = 'default'",
      name: "index_auto_reply_rules_on_one_default_per_destination"
    add_index :auto_reply_rules, %i[social_destination_id keyword],
      unique: true,
      where: "rule_type = 'keyword'",
      name: "index_auto_reply_rules_on_keyword_per_destination"

    create_table :auto_reply_events do |t|
      t.references :social_destination, null: false, foreign_key: true
      t.string :source, null: false
      t.string :event_type, null: false
      t.string :provider_comment_id, null: false
      t.text :comment_text, null: false
      t.string :status, null: false
      t.string :safe_error_code
      t.timestamps
    end

    add_index :auto_reply_events, %i[social_destination_id provider_comment_id],
      unique: true,
      name: "index_auto_reply_events_on_destination_and_provider_comment"
    add_index :auto_reply_events, :status

    create_table :automation_controls do |t|
      t.string :scope_key, null: false
      t.boolean :auto_responder_paused, null: false
      t.timestamps
    end

    add_index :automation_controls, :scope_key, unique: true
  end
end
