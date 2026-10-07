class CreateWorkflowReliabilityRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_runs do |table|
      table.references :workflowable, polymorphic: true, null: false
      table.string :operation_id, null: false
      table.string :operation, null: false
      table.string :stage, null: false
      table.string :status, null: false
      table.string :worker_id
      table.datetime :lease_expires_at
      table.datetime :heartbeat_at
      table.bigint :fencing_token, null: false, default: 0
      table.jsonb :checkpoint, null: false, default: {}
      table.jsonb :metadata, null: false, default: {}
      table.timestamps

      table.index :operation_id, unique: true
      table.index [ :workflowable_type, :workflowable_id, :operation ]
      table.index [ :status, :lease_expires_at ]
    end

    create_table :outbound_attempts do |table|
      table.references :workflow_run, null: false, foreign_key: true
      table.string :attempt_id, null: false
      table.integer :attempt_number, null: false
      table.string :stage, null: false
      table.string :status, null: false
      table.string :idempotency_key
      table.datetime :request_started_at
      table.datetime :sender_stopped_at
      table.datetime :request_timeout_at, null: false
      table.jsonb :provider_reference, null: false, default: {}
      table.string :safe_error_code
      table.text :manual_evidence
      table.string :actor_reference
      table.timestamps

      table.index :attempt_id, unique: true
      table.index [ :workflow_run_id, :stage, :attempt_number ], unique: true,
                  name: :index_outbound_attempts_on_run_stage_number
      table.index [ :workflow_run_id, :status ]
    end

    create_table :workflow_audit_events do |table|
      table.references :workflow_run, null: false, foreign_key: true
      table.references :outbound_attempt, foreign_key: true
      table.string :event_type, null: false
      table.string :stage
      table.string :worker_id
      table.bigint :fencing_token
      table.string :actor_reference
      table.jsonb :details, null: false, default: {}
      table.timestamps

      table.index [ :workflow_run_id, :created_at ]
    end
  end
end
