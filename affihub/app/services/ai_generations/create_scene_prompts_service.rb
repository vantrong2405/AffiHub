# frozen_string_literal: true

class AiGenerations::CreateScenePromptsService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys

  attr_reader :video_project, :video_subject, :scene_prompts, :ai_provider_connection

  # Initializes scene prompt generation from an approved script and saved AI account.
  #
  # @param video_project [VideoProject] the project receiving the scene prompts
  # @param ai_provider_connection_id [Integer] the account saved with the generation
  # @param model_id [String] the account model saved with the generation
  # @param video_subject [String] the topic used for the approved script
  # @param video_script [String] the script approved by the user
  # @param script_approved [Boolean] whether the user approved this script
  # @param scene_count [Integer] the requested number of scenes
  # @return [AiGenerations::CreateScenePromptsService] the configured service
  def initialize(
    video_project:,
    ai_provider_connection_id:,
    model_id:,
    video_subject:,
    video_script:,
    script_approved:,
    scene_count: CONFIGURATION.dig(:generation_profile, :scene_count)
  )
    @video_project = video_project
    @ai_provider_connection_id = ai_provider_connection_id
    @model_id = model_id
    @video_subject = video_subject
    @video_script = video_script
    @script_approved = script_approved
    @scene_count = scene_count
    super()
  end

  # Requests scene prompts only after script approval and account validation.
  #
  # @return [Boolean] whether the configured provider returned usable scene prompts
  def call
    return step_fail!("Project video không tồn tại.") unless video_project&.persisted?
    return step_fail!("Cần duyệt kịch bản trước khi tạo cảnh.") unless @script_approved
    return step_fail!("Kịch bản không được để trống.") if @video_script.blank?
    return false unless step_load_ai_provider_connection
    return false unless step_load_provider_configuration
    return false unless step_validate_ai_provider_connection
    return false unless step_load_access_token
    return false unless step_create_scene_prompts

    step_succeed!
    success?
  end

  private

  def step_load_ai_provider_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
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
    return step_fail!(step_generation_message(:scene_prompts_not_supported)) unless @provider_configuration.dig(:capabilities, :scene_prompt_generation)
    return step_fail!(step_generation_message(:scene_prompts_not_ready)) unless ai_provider_connection.ready?
    return step_fail!(step_generation_message(:scene_prompts_model_missing)) if @model_id.blank?
    return step_fail!(step_generation_message(:scene_prompts_model_unavailable)) unless selected_model_available?

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

  def step_create_scene_prompts
    client_class = @provider_configuration.fetch(:clients).fetch(:generation).constantize
    response = client_class.new(configuration: @provider_configuration).generate_text(
      access_token: @access_token,
      model: @model_id,
      input: scene_prompt
    )
    @scene_prompts = JSON.parse(response)
    return true if valid_scene_prompts?

    @scene_prompts = nil
    step_fail!(step_generation_message(:scene_prompts_invalid_response))
  rescue AiProviderClientError
    step_fail!(step_generation_message(:scene_prompts_failed))
  rescue JSON::ParserError, TypeError
    step_fail!(step_generation_message(:scene_prompts_invalid_response))
  end

  def selected_model_available?
    Array(ai_provider_connection.available_models).any? do |model|
      model.is_a?(Hash) && model["slug"] == @model_id
    end
  end

  def scene_prompt
    <<~PROMPT
      Return only a JSON array containing exactly #{@scene_count} concise visual scene prompts in English.
      Topic: #{video_subject}
      Approved script: #{@video_script}
    PROMPT
  end

  def valid_scene_prompts?
    scene_prompts.is_a?(Array) &&
      scene_prompts.length == @scene_count &&
      scene_prompts.all? { |scene_prompt| scene_prompt.is_a?(String) && scene_prompt.present? }
  end

  def step_generation_message(key)
    case key
    when :scene_prompts_not_supported then "Nhà cung cấp này chưa hỗ trợ tạo gợi ý cảnh."
    when :scene_prompts_not_ready then "Kết nối tài khoản AI chưa sẵn sàng."
    when :scene_prompts_model_missing then "Chọn model AI trước khi tạo gợi ý cảnh."
    when :scene_prompts_model_unavailable then "Model đã chọn không còn trong danh sách của kết nối."
    when :scene_prompts_invalid_response then "Provider không trả danh sách gợi ý cảnh hợp lệ."
    else "Không thể tạo gợi ý cảnh bằng tài khoản AI."
    end
  end
end
