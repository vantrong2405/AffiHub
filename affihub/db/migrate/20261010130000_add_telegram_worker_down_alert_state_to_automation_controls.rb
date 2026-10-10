class AddTelegramWorkerDownAlertStateToAutomationControls < ActiveRecord::Migration[8.1]
  def change
    add_column :automation_controls, :telegram_worker_down_alerted, :boolean, null: false, default: false
  end
end
