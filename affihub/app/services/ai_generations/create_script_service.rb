# frozen_string_literal: true

class AiGenerations::CreateScriptService < ApplicationService
  attr_reader :video_project, :script, :input_form

  # Initializes script generation for one persisted video project.
  #
  # @param video_project [VideoProject] the project receiving the draft script
  # @param inputs [Hash] the required topic, language, tone, and target duration
  # @return [AiGenerations::CreateScriptService] the configured service
  def initialize(video_project:, inputs:)
    @video_project = video_project
    @input_form = AiGenerations::CreateForm.new(inputs.to_h.symbolize_keys)
    super()
  end

  # Requests a draft script only after validating the required user input.
  #
  # @return [Boolean] whether MPT returned a usable script
  def call
    return step_fail!("Project video không tồn tại.") unless video_project&.persisted?
    return step_fail!(input_form.errors.full_messages.to_sentence) unless input_form.valid?
    return false unless step_create_script

    step_succeed!
    success?
  end

  private

  def step_create_script
    response = Mpt::Client.new.generate_script(
      video_subject: input_form.topic,
      video_language: input_form.language,
      paragraph_number: paragraph_number,
      video_script_prompt: "Write a #{input_form.target_duration}-second script in a #{input_form.tone} tone.",
      custom_system_prompt: ""
    )
    @script = response.fetch("video_script")
    return true if @script.present?

    step_fail!("MPT không trả về kịch bản.")
  rescue Mpt::Client::Error => error
    step_fail!(error.code)
  rescue KeyError
    step_fail!("MPT trả về dữ liệu kịch bản không hợp lệ.")
  end

  def paragraph_number
    [ (input_form.target_duration / 30.0).ceil, 1 ].max.clamp(1, 10)
  end
end
