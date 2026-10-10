class WorkflowRuns::ClaimService < ApplicationService
  PUBLICATION_WORKFLOW_CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:publication_workflow)

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
        return unless step_validate_schedule_before_claim(@workflow_run)
        return unless step_reserve_publication_quota(@workflow_run)

        step_assign_lease
        step_record_claim
        step_succeed!
      else
        step_fail!("Workflow đang được worker khác giữ hoặc chưa đến lượt xử lý.")
      end
    end
  end

  def step_reserve_publication_quota(workflow_run)
    return true unless publication_publish_workflow?(workflow_run)

    service = Publications::QuotaReservationService.new(publication_id: workflow_run.workflowable_id)
    return true if service.call

    step_block_publication_for_quota(workflow_run.workflowable)
    step_fail!(service.errors.full_messages.to_sentence)
  end

  def step_validate_schedule_before_claim(workflow_run)
    return true unless publication_publish_workflow?(workflow_run)

    publication = workflow_run.workflowable
    return true unless publication.is_a?(Publication) && publication.schedule_occurrence_id.present?

    schedule_occurrence = ScheduleOccurrence.lock.find_by(id: publication.schedule_occurrence_id)
    return true unless schedule_occurrence

    schedule = Schedule.lock.find(schedule_occurrence.schedule_id)
    return true unless schedule.paused? || schedule.cancelled?
    return true if workflow_run.checkpoint.to_h.stringify_keys["scheduled_manual_confirmation_at"].present?

    step_return_paused_schedule_publication_to_manual_review(
      workflow_run,
      publication,
      schedule_occurrence,
      schedule.paused? ? :schedule_paused : :schedule_cancelled
    )
  end

  def step_return_paused_schedule_publication_to_manual_review(workflow_run, publication, schedule_occurrence, error_key)
    safe_error_code = PUBLICATION_WORKFLOW_CONFIGURATION.fetch(:safe_error_codes).fetch(error_key)
    publication.update!(status: :draft, safe_error_code:)
    workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
    step_mark_occurrence_skipped(schedule_occurrence, publication)
    message = if error_key == :schedule_paused
      "Lịch đã tạm dừng trước khi đăng; bài đã chuyển về bản nháp để bạn duyệt thủ công."
    else
      "Lịch đã bị hủy trước khi đăng; bài đã chuyển về bản nháp để bạn duyệt thủ công."
    end
    step_fail!(message)
  end

  def step_mark_occurrence_skipped(schedule_occurrence, publication)
    return unless schedule_occurrence.scheduled? || schedule_occurrence.dispatched?
    return if step_other_occurrence_publication_started?(schedule_occurrence, publication)

    schedule_occurrence.update!(status: :skipped, processed_at: Time.current)
  end

  def step_other_occurrence_publication_started?(schedule_occurrence, publication)
    statuses = %w[uploading processing published outcome_unknown manual_outcome_confirmed].map do |status|
      Publication.statuses.fetch(status)
    end
    schedule_occurrence.publications.where.not(id: publication.id).where(status: statuses).exists?
  end

  def step_block_publication_for_quota(publication)
    safe_error_code = Rails.application.config_for(:video_workflow).deep_symbolize_keys
      .fetch(:publication_workflow)
      .fetch(:safe_error_codes)
      .fetch(:quota_exhausted)
    publication.update!(status: :failed, safe_error_code:)
    @workflow_run.update!(status: :failed)
  end

  def publication_publish_workflow?(workflow_run)
    workflow_run.workflowable_type == "Publication" &&
      workflow_run.operation == PUBLICATION_WORKFLOW_CONFIGURATION.fetch(:operation) &&
      workflow_run.stage == PUBLICATION_WORKFLOW_CONFIGURATION.fetch(:publish_stage)
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
