# frozen_string_literal: true

class AiGenerations::CompleteService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys
  attr_reader :task_result, :output

  # Initializes output normalization for one MPT task result.
  #
  # @param task_result [Hash] the task status returned by MPT
  # @return [AiGenerations::CompleteService] the configured service
  def initialize(task_result:)
    @task_result = task_result.to_h.deep_symbolize_keys
    super()
  end

  # Returns the generated MP4, voiceover, and subtitle after MPT completes.
  #
  # @return [Boolean] whether the task contains every required output
  def call
    return step_fail!("MPT task chưa hoàn tất.") unless complete?
    return step_fail!("MPT task thiếu file video, voiceover hoặc subtitle.") unless output_files_present?

    @output = {
      clips: task_result.fetch(:videos),
      voiceover: task_result.fetch(:audio_file),
      subtitle: task_result.fetch(:subtitle_path),
      preview_mp4: task_result.fetch(:combined_videos).first
    }
    step_succeed!
    success?
  end

  private

  def complete?
    task_result[:state] == CONFIGURATION.dig(:task_states, :complete)
  end

  def output_files_present?
    videos = task_result[:videos]
    combined_videos = task_result[:combined_videos]
    videos.is_a?(Array) &&
      videos.present? &&
      videos.all? { |video_path| video_path.is_a?(String) && video_path.present? } &&
      combined_videos.is_a?(Array) &&
      combined_videos.present? &&
      combined_videos.all? { |video_path| video_path.is_a?(String) && video_path.present? } &&
      task_result[:audio_file].is_a?(String) &&
      task_result[:audio_file].present? &&
      task_result[:subtitle_path].is_a?(String) &&
      task_result[:subtitle_path].present?
  end
end
