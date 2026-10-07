class CreateProjectMediaAssets < ActiveRecord::Migration[8.1]
  # Creates the table for project-owned background and logo images.
  #
  # @return [void]
  def change
    create_table :project_media_assets do |table|
      table.references :video_project, null: false, foreign_key: true
      table.timestamps
    end
  end
end
