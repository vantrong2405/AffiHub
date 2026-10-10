# frozen_string_literal: true

class AiGenerations::ShowService < ApplicationService
  SUBMISSION_STAGE = AiGenerations::SubmitService::SUBMISSION_STAGE

  attr_reader :ai_generation, :outbound_attempt, :video_project

  # Initializes a project-scoped AI generation page query.
  #
  # @param video_project_id [Integer] the project that owns the generation
  # @param ai_generation_id [Integer] the generation to display
  # @return [AiGenerations::ShowService] the configured service
  def initialize(video_project_id:, ai_generation_id:)
    @video_project_id = video_project_id
    @ai_generation_id = ai_generation_id
    super()
  end

  # Loads the selected project's AI generation.
  #
  # @return [Boolean] whether the generation page was loaded
  def call
    step_load_video_project
    step_load_ai_generation
    step_load_outbound_attempt
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_load_ai_generation
    @ai_generation = video_project.ai_generations.find(@ai_generation_id)
  end

  def step_load_outbound_attempt
    workflow_run = ai_generation.workflow_run
    return unless workflow_run

    @outbound_attempt = workflow_run.outbound_attempts.for_stage(SUBMISSION_STAGE).first
  end
end
