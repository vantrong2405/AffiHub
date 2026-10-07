require "fileutils"
require "json"
require "open3"
require "tmpdir"

class RenderVersions::RenderService < ApplicationService
  WORKFLOW_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
  MEDIA_CONFIGURATION = WORKFLOW_CONFIGURATION.fetch(:media)
  RENDER_PROFILE = WORKFLOW_CONFIGURATION.fetch(:render_profile)
  MISSING_FFMPEG_MESSAGE = "Không tìm thấy FFmpeg trên worker."
  TIMEOUT_MESSAGE = "Render vượt quá giới hạn thời gian cho phép."
  FAILURE_MESSAGE = "Không thể render video với cấu hình hiện tại."
  PROCESS_OUTPUT_MAX_BYTES = 1_048_576

  class RenderFailure < StandardError
  end

  class MissingFfmpeg < StandardError
  end

  class ProcessTimeout < StandardError
  end

  # Initializes a worker service for one persisted render version.
  #
  # @param render_version_id [Integer] the version to render
  # @return [RenderVersions::RenderService] the configured render service
  def initialize(render_version_id:)
    @render_version_id = render_version_id
    super()
  end

  # Renders an immutable MP4 version and measures its output with ffprobe.
  #
  # @return [Boolean] whether the render completed successfully
  def call
    return false unless step_load_render_version
    return step_succeed! && success? if @skip_render
    return false unless step_validate_edit_config

    Dir.mktmpdir("affihub-render") do |temporary_directory|
      step_render(temporary_directory)
    end

    step_succeed!
    success?
  rescue MissingFfmpeg
    step_fail_render(MISSING_FFMPEG_MESSAGE)
  rescue ProcessTimeout
    step_fail_render(TIMEOUT_MESSAGE)
  rescue StandardError
    step_fail_render(FAILURE_MESSAGE)
  end

  private

  def step_load_render_version
    @render_version = RenderVersion.find_by(id: @render_version_id)
    return step_fail!(FAILURE_MESSAGE) unless @render_version

    @render_version.with_lock do
      if @render_version.ready? || @render_version.processing?
        @skip_render = true
      else
        @render_version.update!(status: :processing, render_error: nil)
      end
    end
    true
  end

  def step_validate_edit_config
    validator = RenderVersions::EditConfigValidator.new(
      video_project: @render_version.video_project,
      source_asset: @render_version.source_asset,
      edit_config: @render_version.edit_config
    )
    return true if validator.call

    step_fail_render(FAILURE_MESSAGE)
    false
  end

  def step_render(temporary_directory)
    source_path = step_stage_blob(@render_version.source_asset.file.blob, temporary_directory, "source.mp4")
    project_media_paths = step_stage_project_media(temporary_directory)
    source_asset_paths = step_stage_background_video(temporary_directory)
    output_path = File.join(temporary_directory, "render.mp4")
    command_builder = RenderVersions::CommandBuilder.new(
      render_version: @render_version,
      source_path:,
      output_path:,
      temporary_directory:,
      project_media_paths:,
      source_asset_paths:
    )

    step_run_process([ MEDIA_CONFIGURATION.fetch(:ffmpeg_command), *command_builder.arguments ], :ffmpeg)
    metadata = step_probe_output(output_path)
    step_attach_render(output_path, metadata)
  end

  def step_stage_project_media(temporary_directory)
    asset_ids = @render_version.edit_config.fetch("overlays").filter_map do |overlay|
      overlay["project_media_asset_id"] if overlay["type"] == "logo"
    end
    background = @render_version.edit_config.dig("canvas", "background")
    asset_ids << background.fetch("project_media_asset_id") if background.fetch("type") == "image"

    asset_ids.uniq.each_with_object({}) do |asset_id, paths|
      asset = @render_version.video_project.project_media_assets.find(asset_id)
      extension = { "image/png" => ".png", "image/jpeg" => ".jpg", "image/webp" => ".webp" }.fetch(asset.file.content_type)
      paths[asset.id] = step_stage_blob(asset.file.blob, temporary_directory, "project-media-#{asset.id}#{extension}")
    end
  end

  def step_stage_background_video(temporary_directory)
    background = @render_version.edit_config.dig("canvas", "background")
    return {} unless background.fetch("type") == "video"

    source_asset = @render_version.video_project.source_assets.find(background.fetch("source_asset_id"))
    path = step_stage_blob(source_asset.file.blob, temporary_directory, "background-source-#{source_asset.id}.mp4")
    { source_asset.id => path }
  end

  def step_stage_blob(blob, temporary_directory, filename)
    destination = File.join(temporary_directory, filename)
    blob.open do |source_file|
      FileUtils.cp(source_file.path, destination)
    end
    destination
  end

  def step_run_process(arguments, command_type, max_output_bytes = PROCESS_OUTPUT_MAX_BYTES)
    Open3.popen3(*arguments, pgroup: true) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stdout_reader = Thread.new { step_read_output(stdout, max_output_bytes) }
      stderr_reader = Thread.new { step_read_output(stderr, max_output_bytes) }
      unless wait_thread.join(process_timeout(command_type))
        step_stop_process_group(wait_thread)
        stdout_reader.join
        stderr_reader.join
        raise ProcessTimeout
      end

      stdout_text = stdout_reader.value
      stderr_reader.value
      raise RenderFailure unless wait_thread.value.success?

      stdout_text
    end
  rescue Errno::ENOENT
    raise MissingFfmpeg if command_type == :ffmpeg

    raise RenderFailure
  end

  def step_read_output(stream, max_output_bytes)
    output = +""
    stream.each_line do |line|
      output << line if output.bytesize < max_output_bytes
    end
    output.byteslice(0, max_output_bytes)
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

  def step_probe_output(output_path)
    probe_arguments = [
      MEDIA_CONFIGURATION.fetch(:ffprobe_command),
      "-v", "error",
      "-show_entries", "format=duration:stream=codec_type,codec_name,width,height,r_frame_rate",
      "-of", "json",
      output_path
    ]
    probe_output = step_run_process(probe_arguments, :ffprobe, MEDIA_CONFIGURATION.fetch(:ffprobe_max_output_bytes))
    probe_data = JSON.parse(probe_output)
    video_stream = probe_data.fetch("streams").find { |stream| stream["codec_type"] == "video" }
    raise RenderFailure unless video_stream

    audio_stream = probe_data.fetch("streams").find { |stream| stream["codec_type"] == "audio" }
    duration = Float(probe_data.fetch("format").fetch("duration"))
    raise RenderFailure unless duration.positive? && duration.finite?

    {
      "duration_seconds" => duration,
      "file_size_bytes" => File.size(output_path),
      "video_codec" => video_stream.fetch("codec_name"),
      "width" => video_stream.fetch("width"),
      "height" => video_stream.fetch("height"),
      "frame_rate" => video_stream.fetch("r_frame_rate"),
      "has_audio" => audio_stream.present?,
      "audio_codec" => audio_stream&.fetch("codec_name")
    }
  rescue KeyError, JSON::ParserError, ArgumentError
    raise RenderFailure
  end

  def step_attach_render(output_path, metadata)
    filename = "render-#{@render_version.id}-v#{@render_version.version_number}.mp4"
    blob = File.open(output_path, "rb") do |render_file|
      ActiveStorage::Blob.create_and_upload!(
        io: render_file,
        filename:,
        content_type: "video/mp4",
        identify: false
      )
    end

    RenderVersion.transaction do
      @render_version.file.attach(blob)
      @render_version.update!(metadata:, status: :ready, render_error: nil)
    end
  end

  def step_fail_render(message)
    @render_version&.update!(status: :failed, render_error: message)
    step_fail!(message)
    false
  end

  def process_timeout(command_type)
    return MEDIA_CONFIGURATION.fetch(:ffprobe_timeout_seconds) if command_type == :ffprobe

    MEDIA_CONFIGURATION.fetch(:ffmpeg_timeout_seconds)
  end
end
