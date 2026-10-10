class OutboundAttempts::StartService < ApplicationService
  attr_reader :outbound_attempt

  # Initializes a durable outbound attempt before its provider request starts.
  #
  # @param workflow_run_id [Integer] the workflow run owning the request
  # @param worker_id [String] the worker sending the request
  # @param fencing_token [Integer] the worker's current fencing token
  # @param stage [String] the external action being sent
  # @param request_timeout_at [Time] the end of the provider request window
  # @param idempotency_key [String, nil] the stable key passed to a provider when supported
  # @return [OutboundAttempts::StartService] the configured service
  def initialize(workflow_run_id:, worker_id:, fencing_token:, stage:, request_timeout_at:, idempotency_key: nil)
    @workflow_run_id = workflow_run_id
    @worker_id = worker_id
    @fencing_token = fencing_token
    @stage = stage
    @request_timeout_at = request_timeout_at
    @idempotency_key = idempotency_key
    super()
  end

  # Persists a submitting attempt before the provider call can create a side effect.
  #
  # @return [Boolean] whether a new attempt was recorded
  def call
    step_start_outbound_attempt
    success?
  end

  private

  def step_start_outbound_attempt
    WorkflowRun.transaction do
      workflow_run = WorkflowRun.lock.find_by(id: @workflow_run_id)

      if !step_current_lease?(workflow_run)
        step_fail!("Lease đã hết hạn hoặc worker không còn quyền gửi request.")
      elsif @stage.blank? || @request_timeout_at.blank? || @request_timeout_at <= Time.current
        step_fail!("Stage hoặc thời hạn request không hợp lệ.")
      elsif step_find_unresolved_attempt(workflow_run)
        step_fail!("Cần đối soát outbound attempt trước khi gửi lại.")
      elsif step_reserve_publication_quota(workflow_run)
        step_create_attempt(workflow_run)
        step_record_attempt_started(workflow_run)
        step_succeed!
      end
    end
  end

  def step_reserve_publication_quota(workflow_run)
    publication = workflow_run.workflowable
    return true unless publication.is_a?(Publication)

    service = Publications::QuotaReservationService.new(publication_id: publication.id)
    return true if service.call

    step_fail!(service.errors.full_messages.to_sentence)
  end

  def step_current_lease?(workflow_run)
    workflow_run&.running? && workflow_run.worker_id == @worker_id &&
      workflow_run.fencing_token == @fencing_token &&
      workflow_run.lease_expires_at.present? && workflow_run.lease_expires_at > Time.current
  end

  def step_find_unresolved_attempt(workflow_run)
    workflow_run.outbound_attempts.find_by(status: unresolved_attempt_statuses).tap do |attempt|
      @outbound_attempt = attempt if attempt
    end
  end

  def step_create_attempt(workflow_run)
    attempt_number = workflow_run.outbound_attempts.where(stage: @stage).maximum(:attempt_number).to_i + 1
    @outbound_attempt = workflow_run.outbound_attempts.create!(
      attempt_id: SecureRandom.uuid,
      attempt_number:,
      stage: @stage,
      status: :submitting,
      idempotency_key: @idempotency_key,
      request_started_at: Time.current,
      request_timeout_at: @request_timeout_at
    )
  end

  def step_record_attempt_started(workflow_run)
    workflow_run.workflow_audit_events.create!(
      outbound_attempt: @outbound_attempt,
      event_type: "outbound_attempt_started",
      stage: @stage,
      worker_id: @worker_id,
      fencing_token: @fencing_token,
      details: { attempt_id: @outbound_attempt.attempt_id }
    )
  end

  def unresolved_attempt_statuses
    %w[submitting outcome_unknown].map { |status| OutboundAttempt.statuses.fetch(status) }
  end
end
