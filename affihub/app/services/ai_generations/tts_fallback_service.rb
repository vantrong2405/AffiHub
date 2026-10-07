# frozen_string_literal: true

class AiGenerations::TtsFallbackService < ApplicationService
  VIENEU_CONFIGURATION = Rails.application.config_for(:vieneu).deep_symbolize_keys
  AZURE_CONFIGURATION = Rails.application.config_for(:azure_speech).deep_symbolize_keys
  attr_reader :provider, :audio_data, :response_format, :error_code

  # Initializes VieNeu synthesis with an optional consented Azure fallback.
  #
  # @param text [String] the narration text
  # @param azure_estimate [Hash] the Azure quote tied to this text and voice
  # @param azure_consented [Boolean] whether the user confirmed the Azure quote
  # @return [AiGenerations::TtsFallbackService] the configured service
  def initialize(text:, azure_estimate: {}, azure_consented: false)
    @text = text.to_s
    @azure_estimate = azure_estimate.to_h.deep_symbolize_keys
    @azure_consented = azure_consented
    @azure_voice = AZURE_CONFIGURATION.fetch(:voice)
    super()
  end

  # Uses VieNeu first and only calls Azure after a fresh estimate and consent.
  #
  # @return [Boolean] whether a WAV narration was generated
  def call
    return step_fail!("Nội dung giọng đọc không được để trống.") if @text.blank?

    return finish_success if synthesize_with_vieneu

    return step_fail!("VieNeu TTS không khả dụng; Azure cần báo giá hiện hành và xác nhận chi phí.") unless azure_fallback_allowed?

    synthesize_with_azure
    success?
  end

  private

  def synthesize_with_vieneu
    @audio_data = Vieneu::Client.new.synthesize(text: @text, voice: VIENEU_CONFIGURATION.fetch(:voice_name))
    @provider = "vieneu"
    @response_format = VIENEU_CONFIGURATION.fetch(:response_format)
    true
  rescue Vieneu::Client::Error => error
    @error_code = error.code
    false
  end

  def synthesize_with_azure
    @audio_data = AzureSpeech::Client.new.synthesize(text: @text, voice: @azure_voice)
    @provider = "azure_speech"
    @response_format = "wav"
    step_succeed!
    true
  rescue AzureSpeech::Client::Error => error
    @error_code = error.code
    step_fail!("Azure Speech TTS không tạo được audio.")
  end

  def azure_fallback_allowed?
    @azure_consented == true &&
      estimate_matches_input? &&
      estimate_is_current? &&
      estimate_has_valid_amount? &&
      AZURE_CONFIGURATION[:endpoint].present? &&
      AZURE_CONFIGURATION[:api_key].present? &&
      AZURE_CONFIGURATION[:region].present?
  end

  def estimate_matches_input?
    @azure_estimate[:input_snapshot] == { text: @text, voice: @azure_voice }
  end

  def estimate_is_current?
    estimated_at = @azure_estimate[:estimated_at]
    return false unless estimated_at.respond_to?(:to_time)

    estimate_age = Time.current - estimated_at.to_time
    estimate_age >= 0 && estimate_age <= AZURE_CONFIGURATION.fetch(:estimate_max_age_seconds)
  end

  def estimate_has_valid_amount?
    amount = BigDecimal(@azure_estimate[:amount].to_s)
    amount.finite? && amount >= 0 &&
      @azure_estimate[:currency].present? &&
      @azure_estimate[:source].present?
  rescue ArgumentError
    false
  end

  def finish_success
    step_succeed!
    success?
  end
end
