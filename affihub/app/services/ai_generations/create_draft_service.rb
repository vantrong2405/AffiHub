# frozen_string_literal: true

class AiGenerations::CreateDraftService < ApplicationService
  attr_reader :video_project, :ai_generation, :input_form, :ai_provider_connection,
    :ai_provider_connections

  # Initializes a persisted AI generation draft for one project.
  #
  # @param video_project_id [Integer] the project receiving the generation
  # @param inputs [Hash] the required topic, language, tone, and duration
  # @return [AiGenerations::CreateDraftService] the configured service
  def initialize(video_project_id:, inputs:)
    @video_project_id = video_project_id
    @inputs = inputs.to_h.symbolize_keys
    super()
  end

  # Generates a script and saves its inputs for the approval workflow.
  #
  # @return [Boolean] whether the script-ready generation was saved
  def call
    return false unless step_load_video_project
    return false unless step_create_script
    return false unless step_persist_generation

    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find_by(id: @video_project_id)
    return step_fail!("Project video không tồn tại.") unless video_project

    @ai_provider_connections = AiProviderConnection.ready_for_script_generation
    true
  end

  def step_create_script
    script_service = AiGenerations::CreateScriptService.new(video_project:, inputs: @inputs)
    return step_fail!(script_service.errors.full_messages.to_sentence) unless script_service.call

    @input_form = script_service.input_form
    @ai_provider_connection = script_service.ai_provider_connection
    @script = script_service.script
    true
  end

  def step_persist_generation
    input_snapshot = input_form.attributes.merge(
      ai_provider_connection_id: ai_provider_connection.id,
      llm_provider: ai_provider_connection.provider,
      llm_model: ai_provider_connection.selected_model,
      video_subject: input_form.topic,
      video_script: @script,
      script_approved: false,
      scenes: []
    )
    @ai_generation = video_project.ai_generations.create!(
      correlation_id: SecureRandom.uuid,
      status: :script_ready,
      input_snapshot: input_snapshot
    )
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end
end
