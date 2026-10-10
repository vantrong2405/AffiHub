class AddAutoPublishPauseToAutomationControls < ActiveRecord::Migration[8.1]
  def change
    add_column :automation_controls, :auto_publish_paused, :boolean, null: false, default: false
  end
end
