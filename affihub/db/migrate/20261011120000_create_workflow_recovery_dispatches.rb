# frozen_string_literal: true

class CreateWorkflowRecoveryDispatches < ActiveRecord::Migration[8.1]
  def change
    create_table :recovery_dispatches do |table|
      table.references :workflow_run, null: false, foreign_key: true
      table.bigint :fencing_token, null: false
      table.timestamps

      table.index [ :workflow_run_id, :fencing_token ], unique: true,
                  name: :index_recovery_dispatches_on_run_and_fencing_token
    end
  end
end
