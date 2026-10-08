# frozen_string_literal: true

class AiGenerations::CreatePromptsService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
  PROFILE = CONFIGURATION.fetch(:generation_profile)

  attr_reader :video_project, :ai_generation, :video_script, :script_approved

  # Initializes scene prompt generation for one saved AI draft.
  #
  # @param video_project_id [Integer] the project that owns the draft
  # @param ai_generation_id [Integer] the draft receiving the prompts
  # @param video_script [String] the script being approved
  # @param script_approved [Boolean] whether the user approved the script
  # @return [AiGenerations::CreatePromptsService] the configured service
  def initialize(video_project_id:, ai_generation_id:, video_script:, script_approved:)
    @video_project_id = video_project_id
    @ai_generation_id = ai_generation_id
    @video_script = video_script.to_s
    @script_approved = ActiveModel::Type::Boolean.new.cast(script_approved)
    super()
  end

  # Saves the approved script and its generated scene prompts.
  #
  # @return [Boolean] whether the scene prompts were saved
  def call
    step_load_generation
    return false unless step_validate_approval
    return false unless step_save_approved_script
    return false unless step_create_scene_prompts
    return false unless step_save_scene_prompts

    step_succeed!
    success?
  end

  private

  def step_load_generation
    @video_project = VideoProject.find(@video_project_id)
    @ai_generation = video_project.ai_generations.find(@ai_generation_id)
    @input_snapshot = ai_generation.input_snapshot.deep_symbolize_keys
  end

  def step_validate_approval
    return true if @script_approved && @video_script.present?

    step_fail!("Cần duyệt kịch bản trước khi tạo cảnh.")
  end

  def step_save_approved_script
    @input_snapshot = @input_snapshot.merge(video_script: @video_script, script_approved: true)
    ai_generation.update!(input_snapshot: @input_snapshot, estimate_snapshot: {}, status: :script_ready)
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  def step_create_scene_prompts
    service = AiGenerations::CreateScenePromptsService.new(
      video_project: video_project,
      ai_provider_connection_id: @input_snapshot.fetch(:ai_provider_connection_id),
      model_id: @input_snapshot.fetch(:llm_model),
      video_subject: @input_snapshot.fetch(:video_subject),
      video_script: @video_script,
      script_approved: @script_approved,
      scene_count: @input_snapshot.fetch(:scene_count)
    )
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @scene_prompts = service.scene_prompts
    true
  rescue KeyError
    step_fail!("Kết nối AI đã lưu không hợp lệ. Hãy tạo lại kịch bản.")
  end

  def step_save_scene_prompts
    scenes = @scene_prompts.map do |scene_prompt|
      {
        prompt: scene_prompt,
        duration: @input_snapshot.fetch(:scene_duration),
        resolution: @input_snapshot.fetch(:resolution),
        aspect_ratio: PROFILE.fetch(:video_aspect),
        approved: false
      }
    end
    @input_snapshot = @input_snapshot.merge(scenes: scenes)
    ai_generation.update!(input_snapshot: @input_snapshot, status: :prompts_ready)
    true
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end
end
