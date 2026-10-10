class AutoResponder::ProcessService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:statuses)
    .fetch(:auto_reply_event)
  META_CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers)

  attr_reader :workflow_run, :event, :outbound_attempt

  # Initializes one worker attempt for a persisted public comment workflow.
  #
  # @param workflow_run_id [Integer] the workflow to process
  # @param worker_id [String] the worker's stable lease identifier
  # @param client [Meta::Client, nil] an optional Meta client for provider-boundary tests
  # @return [AutoResponder::ProcessService] the configured service
  def initialize(workflow_run_id:, worker_id:, client: nil)
    @workflow_run_id = workflow_run_id
    @worker_id = worker_id
    @client = client
    super()
  end

  # Claims the workflow, records an outbound attempt, and sends one fixed reply.
  #
  # @return [Boolean] whether Meta confirmed the reply
  def call
    step_load_workflow
    return false unless success?

    step_check_pause_and_claim
    return false unless success?

    step_load_comment_context
    return false unless success?

    step_select_reply
    return false unless success?

    step_start_outbound_attempt
    return false unless success?

    step_send_reply
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_workflow
    @workflow_run = WorkflowRun.find_by(id: @workflow_run_id)
    return step_fail!("Không tìm thấy workflow auto-reply.") unless workflow_run

    step_succeed!
  end

  def step_check_pause_and_claim
    control = AutomationControl.current
    control.with_lock do
      if control.auto_responder_paused?
        step_fail!("Tự động trả lời bình luận đang tạm dừng.")
        next
      end

      claim_service = WorkflowRuns::ClaimService.new(workflow_run_id: @workflow_run_id, worker_id: @worker_id)
      if claim_service.call
        @workflow_run = claim_service.workflow_run
        @fencing_token = claim_service.fencing_token
        step_succeed!
      else
        step_fail!(claim_service.errors.full_messages.to_sentence)
      end
    end
  end

  def step_load_comment_context
    @event = workflow_run.workflowable
    return step_fail!("Workflow không thuộc một bình luận.") unless event.is_a?(AutoReplyEvent)

    @social_destination = event.social_destination
    return step_mark_pre_submit_failure(
      :comment_destination_missing,
      "Đích kết nối của bình luận không còn khả dụng."
    ) unless @social_destination.connected?

    step_succeed!
  end

  def step_select_reply
    selector = AutoResponder::SelectRuleService.new(
      social_destination_id: @social_destination.id,
      comment_text: event.comment_text
    )
    return step_mark_pre_submit_failure(
      :default_rule_missing,
      "Đích này không còn câu trả lời mặc định đang bật."
    ) unless selector.call

    @rule = selector.rule
    @reply_text = selector.reply_text
    step_succeed!
  end

  def step_start_outbound_attempt
    request_timeout = provider_configuration.fetch(:read_timeout_seconds).to_i.seconds
    service = OutboundAttempts::StartService.new(
      workflow_run_id: workflow_run.id,
      worker_id: @worker_id,
      fencing_token: @fencing_token,
      stage: CONFIGURATION.fetch(:reply_stage),
      request_timeout_at: Time.current + request_timeout
    )
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @outbound_attempt = service.outbound_attempt
    step_succeed!
  end

  def step_send_reply
    response = meta_client.reply_to_comment(
      comment_id: event.provider_comment_id,
      page_access_token: @social_destination.access_token,
      message: @reply_text
    )
    return step_mark_outcome_unknown(CONFIGURATION.fetch(:safe_error_codes).fetch(:reply_response_invalid)) unless step_valid_reply_response?(response)

    step_record_outcome(
      event_status: :sent,
      workflow_status: :completed,
      attempt_status: :confirmed,
      audit_event_type: CONFIGURATION.fetch(:audit_events).fetch(:sent),
      provider_reply_id: response.fetch("id")
    )
    step_succeed!
  rescue Meta::Client::Error => error
    if step_ambiguous_error?(error.code)
      step_mark_outcome_unknown(step_safe_error_code(error.code))
    else
      step_mark_failed(step_safe_error_code(error.code))
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    step_mark_outcome_unknown(CONFIGURATION.fetch(:safe_error_codes).fetch(:network_request_failed))
  end

  def step_valid_reply_response?(response)
    response.is_a?(Hash) && response.fetch("id", nil).present?
  end

  def step_ambiguous_error?(error_code)
    CONFIGURATION.fetch(:ambiguous_error_codes).include?(error_code) ||
      CONFIGURATION.fetch(:ambiguous_http_error_prefixes).any? { |prefix| error_code.start_with?(prefix) }
  end

  def step_safe_error_code(error_code)
    safe_error_codes = CONFIGURATION.fetch(:safe_error_codes)
    safe_error_codes.fetch(error_code.to_sym, safe_error_codes.fetch(:reply_failed))
  end

  def step_mark_outcome_unknown(error_code)
    step_record_outcome(
      event_status: :outcome_unknown,
      workflow_status: :outcome_unknown,
      attempt_status: :outcome_unknown,
      audit_event_type: CONFIGURATION.fetch(:audit_events).fetch(:outcome_unknown),
      safe_error_code: error_code
    )
    step_fail!("Chưa xác định được Meta đã nhận câu trả lời hay chưa.")
  end

  def step_mark_failed(error_code)
    return false unless step_record_outcome(
      event_status: :failed,
      workflow_status: :failed,
      attempt_status: :failed,
      audit_event_type: CONFIGURATION.fetch(:audit_events).fetch(:failed),
      safe_error_code: error_code
    )

    step_fail!("Meta từ chối gửi câu trả lời tự động.")
  end

  def step_mark_pre_submit_failure(error_key, message)
    safe_error_code = CONFIGURATION.fetch(:safe_error_codes).fetch(error_key)
    failure_recorded = false

    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find(workflow_run.id)
      unless step_current_claim?
        step_fail!("Lease auto-reply đã hết hạn hoặc worker không còn quyền xử lý.")
        next
      end

      @event = AutoReplyEvent.lock.find(event.id)
      @event.update!(status: :failed, safe_error_code:)
      @workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      step_record_audit_event(
        audit_event_type: CONFIGURATION.fetch(:audit_events).fetch(:failed),
        provider_reply_id: nil,
        safe_error_code:
      )
      failure_recorded = true
    end

    return false unless failure_recorded

    step_fail!(message)
  end

  def step_current_claim?
    workflow_run.running? && workflow_run.worker_id == @worker_id &&
      workflow_run.fencing_token == @fencing_token &&
      workflow_run.lease_expires_at.present? && workflow_run.lease_expires_at > Time.current
  end

  def step_record_outcome(event_status:, workflow_status:, attempt_status:, audit_event_type:,
                          provider_reply_id: nil, safe_error_code: nil)
    now = Time.current
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find(@workflow_run.id)
      @event = AutoReplyEvent.lock.find(event.id)
      @outbound_attempt = OutboundAttempt.lock.find(outbound_attempt.id)
      @outbound_attempt.update!(
        status: attempt_status,
        sender_stopped_at: now,
        provider_reference: provider_reply_id.present? ? { reply_id: provider_reply_id } : {},
        safe_error_code:
      )
      @event.update!(status: event_status, safe_error_code:)
      @workflow_run.update!(status: workflow_status, worker_id: nil, lease_expires_at: nil)
      step_record_audit_event(audit_event_type:, provider_reply_id:, safe_error_code:)
    end
  end

  def step_record_audit_event(audit_event_type:, provider_reply_id:, safe_error_code:)
    @workflow_run.workflow_audit_events.create!(
      event_type: audit_event_type,
      stage: @workflow_run.stage,
      worker_id: @worker_id,
      fencing_token: @fencing_token,
      details: {
        source: event.source,
        event_type: event.event_type,
        social_destination_id: @social_destination.id,
        rule_snapshot: step_rule_snapshot,
        reply_text: @reply_text,
        provider_reply_id:,
        status: event.status,
        safe_error_code:,
        manual_evidence: nil
      }
    )
  end

  def step_rule_snapshot
    return nil unless @rule

    {
      id: @rule.id,
      rule_type: @rule.rule_type,
      keyword: @rule.keyword,
      reply_text: @rule.reply_text
    }
  end

  def provider_configuration
    META_CONFIGURATION.fetch(@social_destination.provider.to_sym)
  end

  def meta_client
    @client ||= Meta::Client.new(provider: @social_destination.provider.to_sym)
  end
end
