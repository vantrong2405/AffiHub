class WorkflowRuns::HeartbeatService < ApplicationService
  attr_reader :workflow_run

  # Initializes a lease heartbeat for its current worker and fencing token.
  #
  # @param workflow_run_id [Integer] the workflow run to renew
  # @param worker_id [String] the worker renewing the lease
  # @param fencing_token [Integer] the worker's current fencing token
  # @param lease_duration [ActiveSupport::Duration, Numeric, nil] optional lease duration
  # @return [WorkflowRuns::HeartbeatService] the configured service
  def initialize(workflow_run_id:, worker_id:, fencing_token:, lease_duration: nil)
    @workflow_run_id = workflow_run_id
    @worker_id = worker_id
    @fencing_token = fencing_token
    @lease_duration = lease_duration || Rails.application.config_for(:video_workflow).fetch(:lease_duration_seconds).seconds
    super()
  end

  # Extends the active worker's lease.
  #
  # @return [Boolean] whether the lease was renewed
  def call
    step_renew_lease
    success?
  end

  private

  def step_renew_lease
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find_by(id: @workflow_run_id)

      if step_current_lease?
        now = Time.current
        @workflow_run.update!(heartbeat_at: now, lease_expires_at: now + @lease_duration)
        step_succeed!
      else
        step_fail!("Lease đã hết hạn hoặc worker không còn quyền cập nhật workflow.")
      end
    end
  end

  def step_current_lease?
    @workflow_run&.running? && @workflow_run.worker_id == @worker_id &&
      @workflow_run.fencing_token == @fencing_token &&
      @workflow_run.lease_expires_at.present? && @workflow_run.lease_expires_at > Time.current
  end
end
