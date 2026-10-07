class WorkflowRuns::ClaimService < ApplicationService
  attr_reader :workflow_run, :fencing_token

  # Initializes an attempt to claim a workflow run for one worker.
  #
  # @param workflow_run_id [Integer] the workflow run to claim
  # @param worker_id [String] the stable identifier of the worker
  # @param lease_duration [ActiveSupport::Duration, Numeric, nil] optional lease duration
  # @return [WorkflowRuns::ClaimService] the configured service
  def initialize(workflow_run_id:, worker_id:, lease_duration: nil)
    @workflow_run_id = workflow_run_id
    @worker_id = worker_id
    @lease_duration = lease_duration || configured_lease_duration
    super()
  end

  # Claims a queued or expired run and advances its fencing token.
  #
  # @return [Boolean] whether the worker received the lease
  def call
    step_claim_workflow_run
    success?
  end

  private

  def step_claim_workflow_run
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find_by(id: @workflow_run_id)

      if @workflow_run.nil?
        step_fail!("Không tìm thấy workflow cần xử lý.")
      elsif @worker_id.blank? || @lease_duration.to_f <= 0
        step_fail!("Worker hoặc thời hạn lease không hợp lệ.")
      elsif step_claimable?
        step_assign_lease
        step_record_claim
        step_succeed!
      else
        step_fail!("Workflow đang được worker khác giữ hoặc chưa đến lượt xử lý.")
      end
    end
  end

  def step_claimable?
    return true if @workflow_run.queued? || @workflow_run.reconciliation_required?

    @workflow_run.running? && @workflow_run.lease_expires_at.present? &&
      @workflow_run.lease_expires_at <= Time.current
  end

  def step_assign_lease
    @fencing_token = @workflow_run.fencing_token + 1
    now = Time.current
    @workflow_run.update!(
      status: :running,
      worker_id: @worker_id,
      fencing_token: @fencing_token,
      heartbeat_at: now,
      lease_expires_at: now + @lease_duration
    )
  end

  def step_record_claim
    @workflow_run.workflow_audit_events.create!(
      event_type: "claimed",
      stage: @workflow_run.stage,
      worker_id: @worker_id,
      fencing_token: @fencing_token
    )
  end

  def configured_lease_duration
    Rails.application.config_for(:video_workflow).fetch(:lease_duration_seconds).seconds
  end
end
