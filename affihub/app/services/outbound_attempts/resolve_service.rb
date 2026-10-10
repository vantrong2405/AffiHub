class OutboundAttempts::ResolveService < ApplicationService
  attr_reader :outbound_attempt

  # Initializes an operator decision for an unresolved outbound attempt.
  #
  # @param outbound_attempt_id [Integer] the attempt to resolve
  # @param decision [String, Symbol] occurred, not_occurred, or unknown
  # @param evidence [String] the operator's evidence for the decision
  # @param provider_reference [String, nil] the provider task URL or ID when the request occurred
  # @param risk_confirmed [Boolean] whether the operator accepts the retry risk for not_occurred
  # @param actor_reference [String] the operator identifier
  # @return [OutboundAttempts::ResolveService] the configured service
  def initialize(outbound_attempt_id:, decision:, evidence:, actor_reference:, provider_reference: nil,
                 risk_confirmed: false)
    @outbound_attempt_id = outbound_attempt_id
    @decision = decision.to_s
    @evidence = evidence
    @actor_reference = actor_reference
    @provider_reference = provider_reference
    @risk_confirmed = risk_confirmed
    super()
  end

  # Records the operator decision without claiming provider confirmation.
  #
  # @return [Boolean] whether the decision was recorded
  def call
    step_resolve_outbound_attempt
    success?
  end

  private

  def step_resolve_outbound_attempt
    attempt = OutboundAttempt.find_by(id: @outbound_attempt_id)
    return step_fail!("Không tìm thấy outbound attempt.") unless attempt

    WorkflowRun.transaction do
      workflow_run = WorkflowRun.lock.find_by(id: attempt.workflow_run_id)
      @outbound_attempt = OutboundAttempt.lock.find_by(id: @outbound_attempt_id)

      if !workflow_run || !@outbound_attempt
        step_fail!("Không tìm thấy workflow cần đối soát.")
      elsif !step_resolvable?
        step_fail!("Outbound attempt không ở trạng thái cần đối soát.")
      elsif !step_valid_decision?
        step_fail!("Quyết định đối soát không hợp lệ.")
      elsif @decision == "not_occurred" && !step_retry_is_safe?
        step_fail!("Chỉ được xác nhận chưa xảy ra khi sender đã dừng và hết cửa sổ request.")
      else
        step_record_manual_decision(workflow_run)
        step_succeed!
      end
    end
  end

  def step_resolvable?
    @outbound_attempt.submitting? || @outbound_attempt.outcome_unknown?
  end

  def step_valid_decision?
    return false unless %w[occurred not_occurred unknown].include?(@decision)
    return false if @actor_reference.blank? || @evidence.blank?
    return false if @decision == "occurred" && @provider_reference.blank?
    return false if @decision == "not_occurred" && @risk_confirmed != true

    true
  end

  def step_retry_is_safe?
    @outbound_attempt.sender_stopped_at.present? && @outbound_attempt.request_timeout_at <= Time.current
  end

  def step_record_manual_decision(workflow_run)
    safe_evidence = Security::SensitiveDataRedactor.new.call(@evidence.to_s)
    safe_actor_reference = Security::SensitiveDataRedactor.new.call(@actor_reference.to_s)
    attempt_attributes = {
      status: attempt_status_for_decision,
      manual_evidence: safe_evidence,
      actor_reference: safe_actor_reference
    }
    attempt_attributes[:provider_reference] = manual_provider_reference if @decision == "occurred"
    @outbound_attempt.update!(attempt_attributes)
    workflow_run.update!(status: workflow_status_for_decision)
    workflow_run.update!(worker_id: nil, lease_expires_at: nil) if @decision == "not_occurred"
    workflow_run.workflow_audit_events.create!(
      outbound_attempt: @outbound_attempt,
      event_type: "manual_outcome_resolved",
      stage: @outbound_attempt.stage,
      actor_reference: safe_actor_reference,
      details: manual_decision_details(safe_evidence, safe_actor_reference)
    )
  end

  def manual_provider_reference
    safe_reference = Security::SensitiveDataRedactor.new.call(@provider_reference.to_s)
    @outbound_attempt.provider_reference.to_h.merge("manual_reference" => safe_reference)
  end

  def manual_decision_details(safe_evidence, safe_actor_reference)
    details = {
      decision: @decision,
      evidence: safe_evidence,
      actor_reference: safe_actor_reference
    }
    details[:provider_reference] = Security::SensitiveDataRedactor.new.call(@provider_reference.to_s) if @decision == "occurred"
    details[:risk_confirmed] = @risk_confirmed if @decision == "not_occurred"
    Security::SensitiveDataRedactor.new.call(details)
  end

  def attempt_status_for_decision
    {
      "occurred" => :manual_outcome_confirmed,
      "not_occurred" => :manual_outcome_not_occurred,
      "unknown" => :outcome_unknown
    }.fetch(@decision)
  end

  def workflow_status_for_decision
    {
      "occurred" => :completed,
      "not_occurred" => :queued,
      "unknown" => :outcome_unknown
    }.fetch(@decision)
  end
end
