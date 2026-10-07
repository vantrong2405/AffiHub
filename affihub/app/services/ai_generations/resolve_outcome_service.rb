# frozen_string_literal: true

class AiGenerations::ResolveOutcomeService < ApplicationService
  SUBMISSION_STAGE = AiGenerations::SubmitService::SUBMISSION_STAGE
  ACTOR_REFERENCE = "local_operator"

  attr_reader :ai_generation, :outbound_attempt, :video_project

  # Initializes a project-scoped manual resolution for an uncertain MPT submission.
  #
  # @param video_project_id [Integer] the project that owns the generation
  # @param ai_generation_id [Integer] the generation with the uncertain submission
  # @param decision [String, Symbol] occurred, not_occurred, or unknown
  # @param evidence [String] the operator's evidence for the decision
  # @param provider_reference [String, nil] the provider URL or task ID when it occurred
  # @param risk_confirmed [Boolean] whether the operator accepts the risk of a retry
  # @return [AiGenerations::ResolveOutcomeService] the configured service
  def initialize(video_project_id:, ai_generation_id:, decision:, evidence:, provider_reference: nil,
                 risk_confirmed: false)
    @video_project_id = video_project_id
    @ai_generation_id = ai_generation_id
    @decision = decision
    @evidence = evidence
    @provider_reference = provider_reference
    @risk_confirmed = risk_confirmed
    super()
  end

  # Records the manual outcome through the outbound attempt resolver.
  #
  # @return [Boolean] whether the decision was saved to the audit trail
  def call
    return false unless step_load_submission

    resolve_service = OutboundAttempts::ResolveService.new(
      outbound_attempt_id: outbound_attempt.id,
      decision: @decision,
      evidence: @evidence,
      actor_reference: ACTOR_REFERENCE,
      provider_reference: @provider_reference,
      risk_confirmed: @risk_confirmed
    )
    return step_fail!(resolve_service.errors.full_messages.to_sentence) unless resolve_service.call

    @outbound_attempt = resolve_service.outbound_attempt
    @ai_generation.reload
    step_succeed!
    success?
  end

  private

  def step_load_submission
    @video_project = VideoProject.find(@video_project_id)
    @ai_generation = video_project.ai_generations.find(@ai_generation_id)
    workflow_run = ai_generation.workflow_run
    @outbound_attempt = workflow_run&.outbound_attempts&.for_stage(SUBMISSION_STAGE)&.first
    return step_fail!("Không tìm thấy outbound attempt cần đối soát.") unless outbound_attempt

    true
  end
end
