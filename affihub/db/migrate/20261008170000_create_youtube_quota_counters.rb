class CreateYoutubeQuotaCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :youtube_quota_counters do |table|
      table.string :bucket, null: false
      table.date :usage_date, null: false
      table.integer :requests_count, null: false
      table.timestamps
    end
    add_index :youtube_quota_counters, [ :bucket, :usage_date ], unique: true
  end
end
