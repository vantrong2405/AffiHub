# frozen_string_literal: true

require "tempfile"

class AiGenerations::PollService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
  COMPLETE_STATE = CONFIGURATION.dig(:task_states, :complete)
  FAILED_STATE = CONFIGURATION.dig(:task_states, :failed)
  PROCESSING_STATE = CONFIGURATION.dig(:task_states, :processing)

  attr_reader :ai_generation

  # Initializes polling for one persisted MPT generation.
  #
  # @param ai_generation_id [Integer] the generation whose task should be polled
  # @return [AiGenerations::PollService] the configured service
  def initialize(ai_generation_id:)
    @ai_generation_id = ai_generation_id
    @retry_poll = false
    @temporary_files = []
    super()
  end

  # Reads the saved MPT task and persists its current state or generated files.
  #
  # @return [Boolean] whether the poll result was handled
  def call
    return false unless step_load_generation
    return step_finish_terminal_generation if ai_generation.completed? || ai_generation.failed?
    return false unless step_validate_generation
    return false unless step_read_task
    return step_finish_terminal_generation if ai_generation.completed? || ai_generation.failed?

    step_process_task_state
  ensure
    step_cleanup_temporary_files
  end

  # Reports whether the poll job should schedule another read.
  #
  # @return [Boolean] whether another poll is required
  def retry_poll?
    @retry_poll == true
  end

  private

  def step_load_generation
    @ai_generation = AiGeneration.find_by(id: @ai_generation_id)
    return true if ai_generation

    step_fail!("Không tìm thấy AI generation cần kiểm tra.")
  end

  def step_finish_terminal_generation
    step_succeed!
    success?
  end

  def step_validate_generation
    return true if ai_generation.processing? && ai_generation.task_id.present?

    step_fail!("AI generation chưa có MPT task đang xử lý.")
  end

  def step_read_task
    @task_result = Mpt::Client.new.task(task_id: ai_generation.task_id).deep_symbolize_keys
    return true if @task_result[:task_id].to_s == ai_generation.task_id.to_s

    step_mark_generation_failed("task_identity_mismatch")
  rescue Mpt::Client::Error => error
    step_handle_client_error(error)
  end

  def step_process_task_state
    @provider_state = Integer(@task_result[:state])
    ai_generation.update!(provider_state: @provider_state)

    case @provider_state
    when PROCESSING_STATE
      step_keep_generation_processing
    when COMPLETE_STATE
      step_persist_completed_outputs
    when FAILED_STATE
      step_mark_generation_failed("provider_task_failed")
    else
      step_mark_generation_failed("invalid_provider_state")
    end
  rescue ArgumentError, TypeError
    step_mark_generation_failed("invalid_provider_state")
  end

  def step_keep_generation_processing
    @retry_poll = true
    ai_generation.update!(safe_error_code: nil)
    step_succeed!
    success?
  end

  def step_persist_completed_outputs
    completion_service = AiGenerations::CompleteService.new(task_result: @task_result)
    return step_mark_generation_failed("invalid_provider_output") unless completion_service.call

    @output = completion_service.output
    return false unless step_download_outputs

    step_attach_outputs
  end

  def step_download_outputs
    @clip_files = @output.fetch(:clips).each_with_index.map do |file_path, index|
      step_download_file(
        file_path:,
        task_id: ai_generation.task_id,
        fallback_filename: "scene-#{index + 1}.mp4",
        content_type: "video/mp4"
      )
    end
    @voiceover_file = step_download_file(
      file_path: @output.fetch(:voiceover),
      task_id: ai_generation.task_id,
      fallback_filename: "voiceover.wav",
      content_type: "audio/wav"
    )
    @subtitle_file = step_download_file(
      file_path: @output.fetch(:subtitle),
      task_id: ai_generation.task_id,
      fallback_filename: "subtitles.srt",
      content_type: "text/plain"
    )
    @preview_file = step_download_file(
      file_path: @output.fetch(:preview_mp4),
      task_id: ai_generation.task_id,
      fallback_filename: "preview.mp4",
      content_type: "video/mp4"
    )
    true
  rescue Mpt::Client::Error => error
    step_handle_client_error(error)
  end

  def step_download_file(file_path:, task_id:, fallback_filename:, content_type:)
    filename = step_output_filename(file_path, fallback_filename)
    tempfile = Tempfile.new([ "ai-generation-", File.extname(filename) ])
    tempfile.binmode
    @temporary_files << tempfile
    Mpt::Client.new.download(file_path:, task_id:, destination: tempfile)
    { io: tempfile, filename:, content_type: }
  end

  def step_upload_file(output_file)
    output_file.fetch(:io).rewind
    ActiveStorage::Blob.create_and_upload!(
      io: output_file.fetch(:io),
      filename: output_file.fetch(:filename),
      content_type: output_file.fetch(:content_type),
      identify: false
    )
  end

  def step_output_filename(file_path, fallback_filename)
    filename = File.basename(URI.parse(file_path).path.to_s)
    filename.presence || fallback_filename
  rescue URI::InvalidURIError
    fallback_filename
  end

  def step_attach_outputs
    terminal_generation = false
    processing_generation = false
    AiGeneration.transaction do
      ai_generation.lock!
      terminal_generation = ai_generation.completed? || ai_generation.failed?
      processing_generation = ai_generation.processing?
      if processing_generation
        @clip_blobs = @clip_files.map { |clip_file| step_upload_file(clip_file) }
        @voiceover_blob = step_upload_file(@voiceover_file)
        @subtitle_blob = step_upload_file(@subtitle_file)
        @preview_blob = step_upload_file(@preview_file)

        ai_generation.clips.attach(@clip_blobs)
        ai_generation.voiceover.attach(@voiceover_blob)
        ai_generation.subtitle.attach(@subtitle_blob)
        ai_generation.preview_video.attach(@preview_blob)

        source_asset = ai_generation.video_project.source_assets.create!(
          source_type: "ai_generated",
          provenance: {
            "provider" => "money_printer_turbo",
            "task_id" => ai_generation.task_id
          }
        )
        source_asset.file.attach(@preview_blob)
        ai_generation.update!(source_asset:, status: :completed, safe_error_code: nil)
      end
    end

    return step_finish_terminal_generation if terminal_generation
    return step_fail!("AI generation không còn ở trạng thái xử lý.") unless processing_generation

    SourceAssets::InspectJob.perform_later(ai_generation.source_asset_id)
    step_succeed!
    success?
  end

  def step_mark_generation_failed(error_code)
    terminal_generation = false
    AiGeneration.transaction do
      ai_generation.lock!
      terminal_generation = ai_generation.completed? || ai_generation.failed?
      unless terminal_generation
        ai_generation.update!(status: :failed, safe_error_code: error_code)
        ai_generation.ai_generation_scenes.where(status: :processing).update_all(
          status: AiGenerationScene.statuses.fetch("failed"),
          safe_error_code: error_code,
          updated_at: Time.current
        )
      end
    end

    return step_finish_terminal_generation if terminal_generation

    step_succeed!
    success?
  end

  def step_handle_client_error(error)
    return step_retry_poll(error.code) if retryable_client_error?(error.code)

    step_mark_generation_failed(error.code)
  end

  def step_retry_poll(error_code)
    processing_generation = false
    AiGeneration.transaction do
      ai_generation.lock!
      if ai_generation.processing?
        ai_generation.update!(safe_error_code: error_code)
        processing_generation = true
      end
    end

    return step_finish_terminal_generation if ai_generation.completed? || ai_generation.failed?
    return step_fail!("AI generation không còn ở trạng thái xử lý.") unless processing_generation

    @retry_poll = true
    step_fail!("Chưa thể lưu kết quả video từ MPT; sẽ thử lại.")
  end

  def retryable_client_error?(error_code)
    error_code == "network_request_failed" || error_code.match?(/\Ahttp_(408|429|5\d{2})\z/)
  end

  def step_cleanup_temporary_files
    @temporary_files.each(&:close!)
  end
end
