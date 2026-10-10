class WorkflowRun < ApplicationRecord
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:workflow_run)

  enum :status, STATUS_CONFIGURATION.fetch(:values), default: STATUS_CONFIGURATION.fetch(:default).to_sym

  belongs_to :workflowable, polymorphic: true

  has_many :outbound_attempts, inverse_of: :workflow_run, dependent: :restrict_with_exception
  has_many :workflow_audit_events, inverse_of: :workflow_run, dependent: :restrict_with_exception
  has_many :recovery_dispatches, class_name: "WorkflowRuns::RecoveryDispatch", inverse_of: :workflow_run,
                                dependent: :destroy

  validates :operation_id, :operation, :stage, presence: true
  validates :operation_id, uniqueness: true
  validates :fencing_token, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
