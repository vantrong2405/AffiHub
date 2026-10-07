class WorkflowRuns::SweepService < ApplicationService
  attr_reader :swept_count

  # Initializes a sweep over expired workflow leases.
  #
  # @return [WorkflowRuns::SweepService] the configured service
  def initialize
    @swept_count = 0
    super()
  end

  # Requeues expired runs without unresolved sends and flags the rest for reconciliation.
  #
  # @return [Boolean] whether the sweep completed
  def call
    step_sweep_expired_runs
    success?
  end

  private

  def step_sweep_expired_runs
    expired_run_ids = WorkflowRun.running.where(lease_expires_at: ..Time.current).pluck(:id)
    expired_run_ids.each { |workflow_run_id| step_sweep_expired_run(workflow_run_id) }
    step_succeed!
  end

  def step_sweep_expired_run(workflow_run_id)
    WorkflowRun.transaction do
      workflow_run = WorkflowRun.lock.find_by(id: workflow_run_id)

      if workflow_run&.running? && workflow_run.lease_expires_at <= Time.current
        next_status = workflow_run.outbound_attempts.where(status: unresolved_attempt_statuses).exists? ?
          :reconciliation_required : :queued
        workflow_run.update!(status: next_status, worker_id: nil, lease_expires_at: nil)
        workflow_run.workflow_audit_events.create!(
          event_type: "lease_expired",
          stage: workflow_run.stage,
          details: { status: next_status.to_s }
        )
        @swept_count += 1
      end
    end
  end

  def unresolved_attempt_statuses
    %w[submitting outcome_unknown].map { |status| OutboundAttempt.statuses.fetch(status) }
  end
end
