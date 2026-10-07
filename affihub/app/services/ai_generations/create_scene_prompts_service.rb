# frozen_string_literal: true

class AiGenerations::CreateScenePromptsService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
  attr_reader :video_project, :video_subject, :scene_prompts

  # Initializes scene prompt generation from an approved script.
  #
  # @param video_project [VideoProject] the project being generated
  # @param video_subject [String] the topic used for the approved script
  # @param video_script [String] the script approved by the user
  # @param script_approved [Boolean] whether the user approved this script
  # @param scene_count [Integer] the requested number of scenes
  # @return [AiGenerations::CreateScenePromptsService] the configured service
  def initialize(video_project:, video_subject:, video_script:, script_approved:, scene_count: CONFIGURATION.dig(:generation_profile, :scene_count))
    @video_project = video_project
    @video_subject = video_subject
    @video_script = video_script
    @script_approved = script_approved
    @scene_count = scene_count
    super()
  end

  # Requests scene prompts only after script approval.
  #
  # @return [Boolean] whether MPT returned usable scene prompts
  def call
    return step_fail!("Project video không tồn tại.") unless video_project&.persisted?
    return step_fail!("Cần duyệt kịch bản trước khi tạo cảnh.") unless @script_approved
    return step_fail!("Kịch bản không được để trống.") if @video_script.blank?

    step_create_scene_prompts
  end

  private

  def step_create_scene_prompts
    response = Mpt::Client.new.generate_terms(
      video_subject:,
      video_script: @video_script,
      amount: @scene_count,
      match_materials_to_script: true
    )
    @scene_prompts = response.fetch("video_terms")
    return step_fail!("MPT không trả đủ gợi ý cảnh.") unless valid_scene_prompts?

    step_succeed!
    success?
  rescue Mpt::Client::Error => error
    step_fail!(error.code)
  rescue KeyError
    step_fail!("MPT trả về dữ liệu cảnh không hợp lệ.")
  end

  def valid_scene_prompts?
    scene_prompts.is_a?(Array) &&
      scene_prompts.length == @scene_count &&
      scene_prompts.all? { |scene_prompt| scene_prompt.is_a?(String) && scene_prompt.present? }
  end
end
