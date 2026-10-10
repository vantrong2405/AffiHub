# frozen_string_literal: true

require "openssl"

class AiGenerations::TtsFallbackCallbackService < ApplicationService
  CALLBACK_CONFIGURATION = Rails.application.config_for(:mpt_tts_callback).deep_symbolize_keys
  AZURE_CONFIGURATION = Rails.application.config_for(:azure_speech).deep_symbolize_keys
  CALLBACK_TIMESTAMP_TOLERANCE = CALLBACK_CONFIGURATION.fetch(:timestamp_tolerance_seconds).to_i.seconds

  attr_reader :audio_data, :ai_generation_scene, :outbound_attempt, :workflow_run

  # Initializes an authenticated MPT request for one approved scene.
  #
  # @param raw_body [String] the exact JSON body received from MPT
  # @param timestamp [String] the signed Unix timestamp from MPT
  # @param signature [String] the HMAC-SHA256 signature from MPT
  # @return [AiGenerations::TtsFallbackCallbackService] the configured service
  def initialize(raw_body:, timestamp:, signature:)
    @raw_body = raw_body.to_s
    @timestamp = timestamp.to_s
    @signature = signature.to_s
    super()
  end

  # Validates the callback, records an Azure attempt, and returns the saved WAV.
  #
  # @return [Boolean] whether the scene WAV is ready for MPT
  def call
    return false unless step_authenticate_callback
    return false unless step_parse_callback
    return false unless step_load_scene
    return false unless step_match_approved_scene
    return false unless step_load_workflow_run
    return success? unless step_handle_existing_attempt
    return false unless step_validate_quote_and_consent
    return false unless step_prepare_workflow_run
    return false unless step_claim_workflow_run
    return false unless step_start_outbound_attempt
    return false unless step_synthesize_audio
    return false unless step_persist_audio

    step_succeed!
    success?
  end

  private

  def step_authenticate_callback
    return step_fail!("Callback MPT chưa được cấu hình.") if callback_secret.blank?
    return step_fail!("Callback MPT có timestamp không hợp lệ.") unless step_timestamp_is_current?
    return step_fail!("Callback MPT có chữ ký không hợp lệ.") unless step_signature_is_valid?

    true
  end

  def step_parse_callback
    payload = JSON.parse(@raw_body)
    return step_fail!("Callback MPT phải là một object JSON.") unless payload.is_a?(Hash)

    @payload = payload.deep_symbolize_keys
    true
  rescue JSON::ParserError
    step_fail!("Callback MPT có nội dung JSON không hợp lệ.")
  end

  def step_load_scene
    ai_generation = AiGeneration.find_by(correlation_id: @payload[:correlation_id])
    @ai_generation_scene = ai_generation&.ai_generation_scenes&.find_by(scene_index: @payload[:scene_index])
    return true if @ai_generation_scene

    step_fail!("Không tìm thấy AI generation hoặc scene đã duyệt.")
  end

  def step_match_approved_scene
    ai_generation = @ai_generation_scene.ai_generation
    generation_status_allows_callback = ai_generation.processing? || ai_generation.submitting?
    return step_fail!("AI generation chưa ở trạng thái xử lý TTS.") unless generation_status_allows_callback
    return step_fail!("Narration callback không khớp nội dung đã duyệt.") unless @payload[:narration] == @ai_generation_scene.narration_snapshot
    return step_fail!("Voice callback không khớp voice đã duyệt.") unless @payload[:voice] == @ai_generation_scene.voice_name
    return true if @ai_generation_scene.processing?
    return true if @ai_generation_scene.completed? && @ai_generation_scene.voiceover.attached?

    step_fail!("Scene chưa ở trạng thái xử lý TTS.")
  end

  def step_load_workflow_run
    @workflow_run = @ai_generation_scene.workflow_run
    true
  end

  def step_handle_existing_attempt
    return true unless @workflow_run

    @outbound_attempt = @workflow_run.outbound_attempts.for_stage(outbound_stage).first
    return true unless @outbound_attempt

    if @outbound_attempt.confirmed? && @ai_generation_scene.voiceover.attached?
      @audio_data = @ai_generation_scene.voiceover.download
      step_succeed!
    else
      step_fail!("Azure TTS fallback đang chờ đối soát.")
    end

    false
  end

  def step_validate_quote_and_consent
    return step_fail!("Báo giá Azure TTS không còn hợp lệ.") unless step_quote_is_current?
    return step_fail!("Azure TTS chưa được xác nhận cho báo giá này.") unless step_consent_matches_quote?

    true
  end

  def step_prepare_workflow_run
    AiGenerationScene.transaction do
      scene = AiGenerationScene.lock.find(@ai_generation_scene.id)
      @workflow_run = scene.workflow_run || scene.create_workflow_run!(
        operation_id: "ai-generation-scene-#{scene.id}-tts-fallback",
        operation: "tts_fallback",
        stage: "azure_speech",
        status: :queued
      )
    end
    true
  rescue ActiveRecord::RecordNotUnique
    @workflow_run = @ai_generation_scene.reload.workflow_run
    !!@workflow_run
  end

  def step_claim_workflow_run
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: @workflow_run.id,
      worker_id:,
      lease_duration: azure_request_timeout + 30.seconds
    )
    return step_fail!("Không thể claim workflow TTS fallback.") unless claim_service.call

    @workflow_run = claim_service.workflow_run
    @fencing_token = claim_service.fencing_token
    true
  end

  def step_start_outbound_attempt
    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: @workflow_run.id,
      worker_id:,
      fencing_token: @fencing_token,
      stage: outbound_stage,
      request_timeout_at: Time.current + azure_request_timeout,
      idempotency_key: "ai-generation-scene-#{@ai_generation_scene.id}-azure-speech"
    )
    return step_fail!("Không thể lưu outbound attempt trước khi gọi Azure.") unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    true
  end

  def step_synthesize_audio
    @audio_data = AzureSpeech::Client.new.synthesize(
      text: @ai_generation_scene.narration_snapshot,
      voice: @ai_generation_scene.voice_name
    )
    true
  rescue AzureSpeech::Client::Error => error
    step_resolve_azure_error(error.code)
    step_fail!("Azure Speech chưa trả được WAV cho scene này.")
  end

  def step_persist_audio
    @ai_generation_scene.voiceover.attach(
      io: StringIO.new(@audio_data),
      filename: "scene-#{@ai_generation_scene.scene_index + 1}-voiceover.wav",
      content_type: "audio/wav"
    )
    @outbound_attempt.update!(
      status: :confirmed,
      sender_stopped_at: Time.current,
      provider_reference: {
        provider: "azure_speech",
        quoted_amount: quote_snapshot.fetch(:amount),
        currency: quote_snapshot.fetch(:currency),
        scene_index: @ai_generation_scene.scene_index
      }
    )
    @ai_generation_scene.update!(status: :completed, safe_error_code: nil)
    @workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
    @workflow_run.workflow_audit_events.create!(
      outbound_attempt: @outbound_attempt,
      event_type: "tts_fallback_completed",
      stage: outbound_stage,
      details: { provider: "azure_speech", scene_index: @ai_generation_scene.scene_index }
    )
    true
  end

  def step_resolve_azure_error(error_code)
    status = ambiguous_azure_result?(error_code) ? :outcome_unknown : :failed
    @outbound_attempt.update!(
      status:,
      sender_stopped_at: Time.current,
      safe_error_code: error_code
    )
    @ai_generation_scene.update!(status:, safe_error_code: error_code)
    @workflow_run.update!(status:, worker_id: nil, lease_expires_at: nil)
    @workflow_run.workflow_audit_events.create!(
      outbound_attempt: @outbound_attempt,
      event_type: "tts_fallback_failed",
      stage: outbound_stage,
      details: { status: status.to_s, safe_error_code: error_code }
    )
  end

  def step_timestamp_is_current?
    timestamp = Integer(@timestamp, 10)
    (Time.current.to_i - timestamp).abs <= CALLBACK_TIMESTAMP_TOLERANCE
  rescue ArgumentError
    false
  end

  def step_signature_is_valid?
    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", callback_secret, "#{@timestamp}.#{@raw_body}")
    return false unless expected_signature.bytesize == @signature.bytesize

    ActiveSupport::SecurityUtils.secure_compare(expected_signature, @signature)
  end

  def step_quote_is_current?
    ai_generation = @ai_generation_scene.ai_generation
    AiGenerationEstimates::FallbackQuoteValidator.new(
      quote: quote_snapshot,
      narration: @ai_generation_scene.narration_snapshot,
      voice: @ai_generation_scene.voice_name,
      currency: ai_generation.estimate_snapshot.deep_symbolize_keys[:currency]
    ).valid?
  end

  def step_consent_matches_quote?
    consent = @ai_generation_scene.consent_snapshot.deep_symbolize_keys
    consent[:confirmed] == true && consent[:estimate] == quote_snapshot
  end

  def quote_snapshot
    @ai_generation_scene.estimate_snapshot.deep_symbolize_keys
  end

  def callback_secret
    CALLBACK_CONFIGURATION.fetch(:secret).to_s
  end

  def worker_id
    @worker_id ||= "mpt-tts-callback-#{SecureRandom.uuid}"
  end

  def outbound_stage
    "azure_tts_scene_#{@ai_generation_scene.scene_index}"
  end

  def azure_request_timeout
    AZURE_CONFIGURATION.fetch(:open_timeout_seconds).to_i.seconds +
      AZURE_CONFIGURATION.fetch(:read_timeout_seconds).to_i.seconds
  end

  def ambiguous_azure_result?(error_code)
    error_code == "network_request_failed" || error_code.start_with?("http_5")
  end
end
