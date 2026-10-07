require "json"
require "tempfile"

class SourceAssets::InspectService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
  MEDIA_CONFIGURATION = CONFIGURATION.fetch(:media)
  PROBE_FAILURE_MESSAGE = "Không thể đọc metadata video. Hãy chọn file MP4/MOV hợp lệ."

  attr_reader :source_asset

  # Initializes inspection for one persisted source asset.
  #
  # @param source_asset_id [Integer] the source asset to inspect
  # @return [SourceAssets::InspectService] the configured service
  def initialize(source_asset_id:)
    @source_asset_id = source_asset_id
    super()
  end

  # Probes a source file and stores its verified media metadata.
  #
  # @return [Boolean] whether inspection succeeded
  def call
    return false unless step_load_source_asset
    return false unless step_claim_source_asset
    return false unless step_inspect_source

    step_succeed!
    success?
  end

  private

  def step_load_source_asset
    @source_asset = SourceAsset.find_by(id: @source_asset_id)
    return step_fail!("Không tìm thấy video cần kiểm tra.") unless @source_asset

    true
  end

  def step_claim_source_asset
    claimed = false
    source_asset.with_lock do
      if source_asset.pending?
        source_asset.update!(status: :processing)
        claimed = true
      end
    end
    return step_fail!("Video không còn ở trạng thái chờ kiểm tra.") unless claimed

    true
  end

  def step_inspect_source
    raise ProbeError unless source_asset.file.attached?

    probe_data = source_asset.file.blob.open do |file|
      step_run_ffprobe(file.path)
    end
    source_asset.update!(media_metadata: step_map_metadata(probe_data), inspection_error: nil, status: :ready)
    true
  rescue ProbeError, ActiveStorage::FileNotFoundError, Errno::ENOENT, IOError, JSON::ParserError, ArgumentError, KeyError, TypeError
    step_mark_source_failed
  end

  def step_run_ffprobe(path)
    output_file = Tempfile.new("affihub-ffprobe")
    process_id = Process.spawn(
      { "LANG" => "C", "PATH" => ENV.fetch("PATH", "/usr/bin:/bin") },
      *step_ffprobe_arguments(path),
      out: output_file,
      err: File::NULL,
      pgroup: true,
      close_others: true,
      unsetenv_others: true
    )
    process_status = step_wait_for_probe(process_id)
    process_id = nil
    raise ProbeError unless process_status.success?

    output_file.rewind
    output = output_file.read(MEDIA_CONFIGURATION.fetch(:ffprobe_max_output_bytes) + 1)
    raise ProbeError if output.bytesize > MEDIA_CONFIGURATION.fetch(:ffprobe_max_output_bytes)

    JSON.parse(output)
  ensure
    step_terminate_probe(process_id) if process_id
    output_file&.close!
  end

  def step_ffprobe_arguments(path)
    [
      MEDIA_CONFIGURATION.fetch(:ffprobe_command),
      "-v", "error",
      "-show_entries", "format=duration:stream=codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate",
      "-of", "json",
      path
    ]
  end

  def step_wait_for_probe(process_id)
    deadline = monotonic_time + MEDIA_CONFIGURATION.fetch(:ffprobe_timeout_seconds)
    loop do
      waited_process_id, process_status = Process.wait2(process_id, Process::WNOHANG)
      return process_status if waited_process_id
      raise ProbeError if monotonic_time >= deadline

      sleep(0.05)
    end
  rescue ProbeError
    step_terminate_probe(process_id)
    raise
  rescue Errno::ECHILD
    raise ProbeError
  end

  def step_terminate_probe(process_id)
    Process.kill("TERM", -process_id)
  rescue Errno::ESRCH
    nil
  ensure
    step_reap_probe(process_id)
  end

  def step_reap_probe(process_id)
    deadline = monotonic_time + 1
    loop do
      waited_process_id, = Process.wait2(process_id, Process::WNOHANG)
      return if waited_process_id
      break if monotonic_time >= deadline

      sleep(0.05)
    end
    Process.kill("KILL", -process_id)
    Process.wait(process_id)
  rescue Errno::ECHILD, Errno::ESRCH
    nil
  end

  def step_map_metadata(probe_data)
    streams = probe_data.fetch("streams", [])
    video_stream = streams.find { |stream| stream["codec_type"] == "video" }
    raise ProbeError unless video_stream

    audio_stream = streams.find { |stream| stream["codec_type"] == "audio" }
    frame_rate = video_stream["avg_frame_rate"].presence || video_stream["r_frame_rate"]
    frame_rate = video_stream["r_frame_rate"] if frame_rate == "0/0"
    raise ProbeError unless frame_rate.to_s.match?(/\A\d+\/[1-9]\d*\z/)

    format_duration = probe_data.fetch("format", {})["duration"]
    duration_seconds = Float(format_duration || video_stream.fetch("duration"))
    raise ProbeError unless duration_seconds.finite? && duration_seconds.positive?

    {
      "duration_seconds" => duration_seconds,
      "file_size_bytes" => source_asset.file.blob.byte_size,
      "video_codec" => video_stream.fetch("codec_name"),
      "width" => Integer(video_stream.fetch("width")),
      "height" => Integer(video_stream.fetch("height")),
      "frame_rate" => frame_rate,
      "has_audio" => audio_stream.present?,
      "audio_codec" => audio_stream&.[]("codec_name")
    }
  end

  def step_mark_source_failed
    source_asset.update!(status: :failed, inspection_error: PROBE_FAILURE_MESSAGE)
    step_fail!(PROBE_FAILURE_MESSAGE)
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  class ProbeError < StandardError
  end
end
