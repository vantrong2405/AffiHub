# frozen_string_literal: true

class AiGenerations::CreateScriptService < ApplicationService
  attr_reader :video_project, :script, :input_form, :ai_provider_connection

  # Initializes script generation for one persisted video project.
  #
  # @param video_project [VideoProject] the project receiving the draft script
  # @param inputs [Hash] the required topic, language, tone, duration, and AI account
  # @return [AiGenerations::CreateScriptService] the configured service
  def initialize(video_project:, inputs:)
    @video_project = video_project
    @input_form = AiGenerations::CreateForm.new(inputs.to_h.symbolize_keys)
    super()
  end

  # Requests a draft script only after validating the required user input and account.
  #
  # @return [Boolean] whether the configured provider returned a usable script
  def call
    return step_fail!("Project video không tồn tại.") unless video_project&.persisted?
    return step_fail!(input_form.errors.full_messages.to_sentence) unless input_form.valid?
    return false unless step_load_ai_provider_connection
    return false unless step_load_provider_configuration
    return false unless step_validate_ai_provider_connection
    return false unless step_load_access_token
    return false unless step_create_script

    step_succeed!
    success?
  end

  private

  def step_load_ai_provider_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: input_form.ai_provider_connection_id)
    return true if ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI.")
  end

  def step_load_provider_configuration
    configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    @provider_configuration = configuration.fetch(:providers).fetch(ai_provider_connection.provider.to_sym)
    true
  rescue KeyError
    step_fail!("Không thể tải cấu hình của tài khoản AI.")
  end

  def step_validate_ai_provider_connection
    return step_fail!("Tài khoản AI chưa có quyền dùng model.") if ai_provider_connection.scope_missing?
    return step_fail!("Nhà cung cấp này chưa hỗ trợ tạo nội dung.") unless @provider_configuration.dig(:capabilities, :inference_enabled)
    return step_fail!(step_generation_message(:script_not_supported)) unless @provider_configuration.dig(:capabilities, :script_generation)
    return step_fail!(step_generation_message(:script_not_ready)) unless ai_provider_connection.ready?
    return step_fail!(step_generation_message(:script_model_missing)) if ai_provider_connection.selected_model.blank?
    return step_fail!(step_generation_message(:script_model_unavailable)) unless selected_model_available?

    true
  end

  def step_load_access_token
    service = AiProviderConnections::AccessTokenService.new(
      ai_provider_connection_id: ai_provider_connection.id
    )
    return step_fail!(service.errors.full_messages.to_sentence) unless service.call

    @access_token = service.access_token
    true
  end

  def step_create_script
    client_class = @provider_configuration.fetch(:clients).fetch(:generation).constantize
    @script = client_class.new(configuration: @provider_configuration).generate_text(
      access_token: @access_token,
      model: ai_provider_connection.selected_model,
      input: script_prompt
    )
    return true if script.present?

    step_fail!(step_generation_message(:script_empty_response))
  rescue AiProviderClientError
    step_fail!(step_generation_message(:script_failed))
  end

  def selected_model_available?
    Array(ai_provider_connection.available_models).any? do |model|
      model.is_a?(Hash) && model["slug"] == ai_provider_connection.selected_model
    end
  end

  def script_prompt
    <<~PROMPT
      Write a video script for the following brief.
      Topic: #{input_form.topic}
      Language: #{input_form.language == "vi" ? "Vietnamese" : "English"}
      Tone: #{input_form.tone}
      Target duration: #{input_form.target_duration} seconds
      Return only the script text, without a title or commentary.
    PROMPT
  end

  def step_generation_message(key)
    case key
    when :script_not_supported then "Nhà cung cấp này chưa hỗ trợ tạo kịch bản."
    when :script_not_ready then "Kết nối tài khoản AI chưa sẵn sàng."
    when :script_model_missing then "Chọn model AI trước khi tạo kịch bản."
    when :script_model_unavailable then "Model đã chọn không còn trong danh sách của kết nối."
    when :script_empty_response then "Provider không trả kịch bản hợp lệ."
    else "Không thể tạo kịch bản bằng tài khoản AI."
    end
  end
end
