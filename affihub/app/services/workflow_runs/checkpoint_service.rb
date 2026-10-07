class WorkflowRuns::CheckpointService < ApplicationService
  attr_reader :workflow_run

  # Initializes a checkpoint update for the worker holding the active lease.
  #
  # @param workflow_run_id [Integer] the workflow run to update
  # @param worker_id [String] the worker saving progress
  # @param fencing_token [Integer] the worker's current fencing token
  # @param stage [String] the completed or active workflow stage
  # @param checkpoint [Hash] serializable progress data
  # @return [WorkflowRuns::CheckpointService] the configured service
  def initialize(workflow_run_id:, worker_id:, fencing_token:, stage:, checkpoint:)
    @workflow_run_id = workflow_run_id
    @worker_id = worker_id
    @fencing_token = fencing_token
    @stage = stage
    @checkpoint = checkpoint
    super()
  end

  # Saves progress only while the worker still holds a live lease.
  #
  # @return [Boolean] whether the checkpoint was saved
  def call
    step_save_checkpoint
    success?
  end

  private

  def step_save_checkpoint
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find_by(id: @workflow_run_id)

      if !step_current_lease?
        step_fail!("Lease đã hết hạn hoặc worker không còn quyền cập nhật workflow.")
      elsif @stage.blank? || !@checkpoint.respond_to?(:to_h)
        step_fail!("Stage hoặc checkpoint không hợp lệ.")
      else
        @workflow_run.update!(stage: @stage, checkpoint: @workflow_run.checkpoint.deep_merge(@checkpoint.to_h.deep_stringify_keys))
        @workflow_run.workflow_audit_events.create!(
          event_type: "checkpoint_saved",
          stage: @stage,
          worker_id: @worker_id,
          fencing_token: @fencing_token,
          details: { stage: @stage }
        )
        step_succeed!
      end
    end
  end

  def step_current_lease?
    @workflow_run&.running? && @workflow_run.worker_id == @worker_id &&
      @workflow_run.fencing_token == @fencing_token &&
      @workflow_run.lease_expires_at.present? && @workflow_run.lease_expires_at > Time.current
  end
end
