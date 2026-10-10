# frozen_string_literal: true

class WorkflowRuns::RecoveryDispatch < ApplicationRecord
  belongs_to :workflow_run, inverse_of: :recovery_dispatches

  validates :fencing_token, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :fencing_token, uniqueness: { scope: :workflow_run_id }
end
