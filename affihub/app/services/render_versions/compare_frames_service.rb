require "base64"
require "fileutils"
require "open3"
require "tmpdir"

class RenderVersions::CompareFramesService < ApplicationService
  MEDIA_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:media)
  FRAME_ERROR_MESSAGE = "Không thể tạo khung hình so sánh."
  TIMEOUT_MESSAGE = "Tạo khung hình so sánh vượt quá giới hạn thời gian."
  INVALID_TIMECODE_MESSAGE = "Timecode phải nằm trong thời lượng của cả source và render."

  attr_reader :frames

  # Initializes a comparison request for one ready render version.
  #
  # @param render_version_id [Integer] the ready render version to compare
  # @param timecodes [Array<Numeric>] timestamps to sample from both videos
  # @return [RenderVersions::CompareFramesService] the configured service
  def initialize(render_version_id:, timecodes:)
    @render_version_id = render_version_id
    @timecodes = timecodes
    @frames = []
    super()
  end

  # Extracts paired source and render frames without changing either video.
  #
  # @return [Boolean] whether all requested frame pairs were created
  def call
    return false unless step_load_render_version
    return false unless step_validate_timecodes

    Dir.mktmpdir("affihub-frame-comparison") do |temporary_directory|
      step_extract_frames(temporary_directory)
    end

    step_succeed!
    success?
  rescue StandardError => error
    @frames = []
    step_fail!(error.is_a?(ProcessTimeout) ? TIMEOUT_MESSAGE : FRAME_ERROR_MESSAGE)
    false
  end

  private

  class ProcessTimeout < StandardError
  end

  def step_load_render_version
    @render_version = RenderVersion.find_by(id: @render_version_id)
    return step_fail!(FRAME_ERROR_MESSAGE) unless @render_version&.ready?
    return step_fail!(FRAME_ERROR_MESSAGE) unless @render_version.source_asset.ready?
    return step_fail!(FRAME_ERROR_MESSAGE) unless @render_version.source_asset.file.attached?
    return step_fail!(FRAME_ERROR_MESSAGE) unless @render_version.file.attached?

    true
  end

  def step_validate_timecodes
    source_duration = Float(@render_version.source_asset.media_metadata.fetch("duration_seconds"))
    render_duration = Float(@render_version.metadata.fetch("duration_seconds"))
    shortest_duration = [ source_duration, render_duration ].min
    return true if valid_timecodes?(shortest_duration)

    step_fail!(INVALID_TIMECODE_MESSAGE)
  rescue KeyError, ArgumentError, TypeError
    step_fail!(INVALID_TIMECODE_MESSAGE)
  end

  def valid_timecodes?(shortest_duration)
    return false unless @timecodes.is_a?(Array) && @timecodes.any?

    @timecodes.all? do |timecode|
      timecode.is_a?(Numeric) && timecode.to_f.finite? && timecode >= 0 && timecode < shortest_duration
    end
  end

  def step_extract_frames(temporary_directory)
    source_path = step_stage_blob(@render_version.source_asset.file.blob, temporary_directory, "source.mp4")
    render_path = step_stage_blob(@render_version.file.blob, temporary_directory, "render.mp4")

    @frames = @timecodes.each_with_index.map do |timecode, index|
      source_frame_path = File.join(temporary_directory, "source-frame-#{index}.jpg")
      render_frame_path = File.join(temporary_directory, "render-frame-#{index}.jpg")
      step_extract_frame(source_path, timecode, source_frame_path)
      step_extract_frame(render_path, timecode, render_frame_path)
      step_frame_result(timecode, source_frame_path, render_frame_path)
    end
  end

  def step_stage_blob(blob, temporary_directory, filename)
    destination = File.join(temporary_directory, filename)
    blob.open do |source_file|
      FileUtils.cp(source_file.path, destination)
    end
    destination
  end

  def step_extract_frame(video_path, timecode, frame_path)
    arguments = [
      MEDIA_CONFIGURATION.fetch(:ffmpeg_command),
      "-v", "error",
      "-ss", format("%.3f", timecode),
      "-i", video_path,
      "-frames:v", "1",
      "-vf", "scale=320:-1",
      "-q:v", "4",
      "-y", frame_path
    ]

    step_run_process(arguments)
    raise FRAME_ERROR_MESSAGE unless File.file?(frame_path) && File.size(frame_path).positive?
  end

  def step_run_process(arguments)
    Open3.popen3(*arguments, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stdout_reader = Thread.new { stdout.each_line { |_line| } }
      stderr_reader = Thread.new { stderr.each_line { |_line| } }
      unless wait_thread.join(MEDIA_CONFIGURATION.fetch(:ffmpeg_timeout_seconds))
        step_stop_process_group(wait_thread)
        stdout_reader.join
        stderr_reader.join
        raise ProcessTimeout
      end

      stdout_reader.join
      stderr_reader.join
      raise FRAME_ERROR_MESSAGE unless wait_thread.value.success?
    end
  rescue Errno::ENOENT
    raise FRAME_ERROR_MESSAGE
  end

  def step_stop_process_group(wait_thread)
    process_id = wait_thread.pid
    Process.kill("TERM", -process_id)
    wait_thread.join(1)
    Process.kill("KILL", -process_id) if wait_thread.alive?
    wait_thread.join
  rescue Errno::ESRCH
    wait_thread.join
  end

  def step_frame_result(timecode, source_frame_path, render_frame_path)
    {
      timestamp_seconds: timecode,
      source_frame: step_frame_data_url(source_frame_path),
      render_frame: step_frame_data_url(render_frame_path)
    }
  end

  def step_frame_data_url(frame_path)
    frame_data = Base64.strict_encode64(File.binread(frame_path))
    "data:image/jpeg;base64,#{frame_data}"
  end
end
