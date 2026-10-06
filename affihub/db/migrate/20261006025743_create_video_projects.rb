class CreateVideoProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :video_projects do |t|
      t.string :title
      t.integer :status, null: false, default: 0

      t.timestamps
    end
  end
end
