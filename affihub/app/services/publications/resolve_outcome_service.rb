class Publications::ResolveOutcomeService < ApplicationService
  # The project that owns the reconciled Publication.
  # @return [VideoProject]
  attr_reader :video_project

  attr_reader :publication, :workflow_run, :outbound_attempt

  # Initializes manual reconciliation for one unresolved Publication.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the Publication being reconciled
  # @param decision [String, Symbol] occurred, not_occurred, or unknown
  # @param evidence [String] the operator's evidence for the decision
  # @param actor_reference [String] the operator identifier
  # @param provider_reference [String, nil] the provider reference when the post occurred
  # @param risk_confirmed [Boolean] whether the operator accepts retry risk
  # @return [Publications::ResolveOutcomeService] the configured service
  def initialize(video_project_id:, publication_id:, decision:, evidence:, actor_reference:, provider_reference: nil,
                 risk_confirmed: false)
    @video_project_id = video_project_id
    @publication_id = publication_id
    @decision = decision.to_s
    @evidence = evidence
    @actor_reference = actor_reference
    @provider_reference = provider_reference
    @risk_confirmed = risk_confirmed
    super()
  end

  # Records an operator decision and updates the Publication's manual outcome state.
  #
  # @return [Boolean] whether the manual outcome was recorded
  def call
    return false unless step_resolve_outcome
    return false unless step_enqueue_safe_retry

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_resolve_outcome
    Publication.transaction do
      @video_project = VideoProject.find(@video_project_id)
      @publication = video_project.publications.lock.find(@publication_id)
      return step_fail!("Publication không cần đối soát thủ công.") unless publication.outcome_unknown?

      @workflow_run = publication.workflow_runs.find_by(operation: "publication_publish", stage: "publish")
      return step_fail!("Không tìm thấy workflow đăng Publication.") unless workflow_run

      @outbound_attempt = step_find_unresolved_attempt
      return step_fail!("Không tìm thấy outbound attempt cần đối soát.") unless outbound_attempt

      return false unless step_record_manual_decision

      workflow_run.update!(checkpoint: {}) if @decision == "not_occurred"
      publication.update!(publication_update_attributes)
    end
  end

  def step_find_unresolved_attempt
    workflow_run.outbound_attempts
      .where(status: unresolved_attempt_statuses)
      .order(attempt_number: :desc)
      .first
  end

  def step_record_manual_decision
    resolver = OutboundAttempts::ResolveService.new(
      outbound_attempt_id: outbound_attempt.id,
      decision: @decision,
      evidence: @evidence,
      actor_reference: @actor_reference,
      provider_reference: @provider_reference,
      risk_confirmed: @risk_confirmed
    )
    return step_fail!(resolver.errors.full_messages.to_sentence) unless resolver.call

    @outbound_attempt = resolver.outbound_attempt
    @workflow_run = workflow_run.reload
    true
  end

  def step_enqueue_safe_retry
    return true unless @decision == "not_occurred"

    Publications::PublishJob.perform_later(workflow_run.id)
    true
  end

  def publication_update_attributes
    attributes = { status: publication_status_for_decision }
    attributes[:provider_reference] = outbound_attempt.provider_reference if @decision == "occurred"
    if @decision == "not_occurred"
      attributes.merge!(
        platform_post_id: nil,
        permalink: nil,
        published_at: nil,
        provider_reference: {}
      )
    end
    attributes
  end

  def publication_status_for_decision
    {
      "occurred" => :manual_outcome_confirmed,
      "not_occurred" => :manual_outcome_not_occurred,
      "unknown" => :outcome_unknown
    }.fetch(@decision)
  end

  def unresolved_attempt_statuses
    %w[submitting outcome_unknown].map { |status| OutboundAttempt.statuses.fetch(status) }
  end
end
