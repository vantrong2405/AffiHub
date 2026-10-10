class AutoResponder::ResolveOutcomeService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :event, :workflow_run, :outbound_attempt

  # Initializes the operator's decision for one ambiguous auto-reply.
  #
  # @param auto_reply_event_id [Integer] the comment event to reconcile
  # @param decision [String, Symbol] whether the reply occurred, did not occur, or remains unknown
  # @param evidence [String] the operator's evidence for the decision
  # @param actor_reference [String] the operator identifier
  # @param provider_reference [String, nil] a provider URL or ID when the reply occurred
  # @param risk_confirmed [Boolean] whether the operator accepts retry risk
  # @return [AutoResponder::ResolveOutcomeService] the configured service
  def initialize(auto_reply_event_id:, decision:, evidence:, actor_reference:, provider_reference: nil,
                 risk_confirmed: false)
    @auto_reply_event_id = auto_reply_event_id
    @decision = decision.to_s
    @evidence = evidence
    @actor_reference = actor_reference
    @provider_reference = provider_reference
    @risk_confirmed = risk_confirmed
    super()
  end

  # Persists a manual outcome without asserting provider confirmation.
  #
  # @return [Boolean] whether the manual decision was recorded
  def call
    step_load_unresolved_event
    return false unless success?

    step_resolve_outcome
    return false unless success?

    step_enqueue_safe_retry if @decision == CONFIGURATION.fetch(:manual_decisions).fetch(:not_occurred)
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_unresolved_event
    @event = AutoReplyEvent.find_by(id: @auto_reply_event_id)
    return step_fail!("Không tìm thấy log tự trả lời.") unless event
    return step_fail!("Log tự trả lời không cần đối soát thủ công.") unless event.outcome_unknown?

    @workflow_run = event.workflow_runs.find_by(
      operation: CONFIGURATION.fetch(:workflow_operation),
      stage: CONFIGURATION.fetch(:reply_stage)
    )
    return step_fail!("Không tìm thấy workflow auto-reply cần đối soát.") unless workflow_run

    @outbound_attempt = step_find_unresolved_attempt
    return step_fail!("Không tìm thấy outbound attempt cần đối soát.") unless outbound_attempt

    step_succeed!
  end

  def step_find_unresolved_attempt
    unresolved_statuses = %w[submitting outcome_unknown].map do |status|
      OutboundAttempt.statuses.fetch(status)
    end
    workflow_run.outbound_attempts.where(status: unresolved_statuses).order(:attempt_number).last
  end

  def step_resolve_outcome
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find(workflow_run.id)
      @event = AutoReplyEvent.lock.find(event.id)
      resolver = OutboundAttempts::ResolveService.new(
        outbound_attempt_id: outbound_attempt.id,
        decision: @decision,
        evidence: @evidence,
        actor_reference: @actor_reference,
        provider_reference: @provider_reference,
        risk_confirmed: @risk_confirmed
      )
      unless resolver.call
        step_fail!(resolver.errors.full_messages.to_sentence)
        next
      end

      @outbound_attempt = resolver.outbound_attempt
      @workflow_run = workflow_run.reload
      @event.update!(status: CONFIGURATION.fetch(:manual_outcome_statuses).fetch(@decision.to_sym))
      step_record_manual_audit
      step_succeed!
    end
  end

  def step_record_manual_audit
    details = {
      decision: @decision,
      evidence: safe_value(@evidence),
      actor_reference: safe_value(@actor_reference),
      source: event.source,
      event_type: event.event_type,
      social_destination_id: event.social_destination_id
    }
    details[:provider_reference] = safe_value(@provider_reference) if @decision == CONFIGURATION.fetch(:manual_decisions).fetch(:occurred)
    details[:risk_confirmed] = @risk_confirmed if @decision == CONFIGURATION.fetch(:manual_decisions).fetch(:not_occurred)

    workflow_run.workflow_audit_events.create!(
      event_type: CONFIGURATION.fetch(:audit_events).fetch(:manual_outcome_resolved),
      stage: workflow_run.stage,
      actor_reference: safe_value(@actor_reference),
      details:
    )
  end

  def step_enqueue_safe_retry
    AutoResponder::ProcessJob.perform_later(workflow_run.id)
  end

  def safe_value(value)
    Security::SensitiveDataRedactor.new.call(value.to_s)
  end
end
