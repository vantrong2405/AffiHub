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
    return false unless step_sweep_expired_runs
    return false unless step_enqueue_recovery_jobs

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
        step_create_recovery_dispatch(workflow_run)
        @swept_count += 1
      end
    end
  end

  def step_enqueue_recovery_jobs
    WorkflowRuns::RecoveryDispatch.order(:id).pluck(:id).each do |dispatch_id|
      return false unless step_enqueue_recovery_dispatch(dispatch_id)
    end
    true
  end

  def step_create_recovery_dispatch(workflow_run)
    return unless step_recovery_job(workflow_run)

    workflow_run.recovery_dispatches.create!(fencing_token: workflow_run.fencing_token)
  end

  def step_enqueue_recovery_dispatch(dispatch_id)
    result = true
    WorkflowRuns::RecoveryDispatch.transaction do
      dispatch = WorkflowRuns::RecoveryDispatch.lock.find_by(id: dispatch_id)

      if dispatch
        recovery_job = step_recovery_job(dispatch.workflow_run)
        job_class, job_arguments = recovery_job if recovery_job

        if recovery_job && job_class.perform_later(*job_arguments)
          dispatch.destroy!
        else
          result = step_fail!("Không thể xếp hàng khôi phục workflow.")
        end
      end
    end

    result
  end

  def step_recovery_job(workflow_run)
    workflowable = workflow_run.workflowable

    case workflowable
    when DriveExport
      [ DriveExports::UploadJob, [ workflowable.id ] ]
    when Publication
      [ Publications::PublishJob, [ workflow_run.id ] ]
    when AutoReplyEvent
      return if workflow_run.outbound_attempts.where(status: unresolved_attempt_statuses).exists?

      [ AutoResponder::ProcessJob, [ workflow_run.id ] ]
    when AiGeneration
      [ AiGenerations::ReconcileJob, [ workflowable.id ] ]
    end
  end

  def unresolved_attempt_statuses
    %w[submitting outcome_unknown].map { |status| OutboundAttempt.statuses.fetch(status) }
  end
end
