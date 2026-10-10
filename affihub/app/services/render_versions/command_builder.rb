class RenderVersions::CommandBuilder
  WORKFLOW_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
  PROFILE_CONFIGURATION = WORKFLOW_CONFIGURATION.fetch(:render_profile)
  MEDIA_CONFIGURATION = WORKFLOW_CONFIGURATION.fetch(:media)

  # Initializes FFmpeg arguments for a validated render version.
  #
  # @param render_version [RenderVersion] the persisted edit configuration
  # @param source_path [String] the staged primary source file
  # @param output_path [String] the unique output file path
  # @param temporary_directory [String] the workspace for text overlay files
  # @param project_media_paths [Hash] staged image paths keyed by project media asset ID
  # @param source_asset_paths [Hash] staged video paths keyed by source asset ID
  # @return [RenderVersions::CommandBuilder] the configured command builder
  def initialize(render_version:, source_path:, output_path:, temporary_directory:, project_media_paths:, source_asset_paths:)
    @render_version = render_version
    @edit_config = render_version.edit_config
    @source_path = source_path
    @output_path = output_path
    @temporary_directory = temporary_directory
    @project_media_paths = project_media_paths
    @source_asset_paths = source_asset_paths
    @input_arguments = []
    @filter_chains = []
    @next_input_index = 1
  end

  # Builds the argument vector without passing through a shell.
  #
  # @return [Array<String>] FFmpeg executable arguments
  def arguments
    input_arguments = step_build_inputs
    step_build_video_filters
    step_build_audio_filters
    step_build_composition_filters
    step_build_overlay_filters
    step_build_output_arguments(input_arguments)
  end

  private

  def step_build_inputs
    @input_arguments = [ "-i", @source_path ]
    step_add_background_input
    step_add_logo_inputs
    @input_arguments
  end

  def step_add_background_input
    background = @edit_config.dig("canvas", "background")

    case background.fetch("type")
    when "image"
      @background_input_index = step_add_image_input(@project_media_paths.fetch(background.fetch("project_media_asset_id")))
    when "video"
      @background_input_index = step_add_video_input(@source_asset_paths.fetch(background.fetch("source_asset_id")))
    end
  end

  def step_add_logo_inputs
    @logo_input_indices = {}

    @edit_config.fetch("overlays").each_with_index do |overlay, overlay_index|
      next unless overlay.fetch("type") == "logo"

      asset_path = @project_media_paths.fetch(overlay.fetch("project_media_asset_id"))
      @logo_input_indices[overlay_index] = step_add_image_input(asset_path)
    end
  end

  def step_add_image_input(path)
    input_index = @next_input_index
    @next_input_index += 1
    @input_arguments.concat([ "-loop", "1", "-framerate", frame_rate.to_s, "-i", path ])
    input_index
  end

  def step_add_video_input(path)
    input_index = @next_input_index
    @next_input_index += 1
    @input_arguments.concat([ "-stream_loop", "-1", "-i", path ])
    input_index
  end

  def step_build_video_filters
    source_label = step_add_delogo_filters
    segment_count = @edit_config.fetch("segments").length
    blur_background = @edit_config.dig("canvas", "background", "type") == "blur"
    raw_labels = step_split_source(source_label, segment_count, blur_background)

    @edit_config.fetch("segments").each_with_index do |segment, segment_index|
      step_add_segment_video_filters(segment, segment_index, raw_labels.fetch(:foreground).fetch(segment_index))
      if blur_background
        step_add_blur_background_filters(segment, segment_index, raw_labels.fetch(:background).fetch(segment_index))
      end
    end

    step_add_segment_concat(segment_count)
    step_add_blur_background_concat(segment_count) if blur_background
  end

  def step_add_delogo_filters
    source_label = "0:v"
    regions = @edit_config.fetch("delogo_regions")
    return source_label if regions.empty?

    regions.each_with_index do |region, region_index|
      output_label = "clean_source_#{region_index}"
      @filter_chains << "[#{source_label}]delogo=x=#{region.fetch('x')}:y=#{region.fetch('y')}:w=#{region.fetch('width')}:h=#{region.fetch('height')}[#{output_label}]"
      source_label = output_label
    end

    source_label
  end

  def step_split_source(source_label, segment_count, blur_background)
    split_count = segment_count * (blur_background ? 2 : 1)
    labels = (0...split_count).map { |label_index| "segment_source_#{label_index}" }
    outputs = labels.map { |label| "[#{label}]" }.join
    @filter_chains << "[#{source_label}]split=#{split_count}#{outputs}"

    {
      foreground: labels.first(segment_count),
      background: blur_background ? labels.drop(segment_count) : []
    }
  end

  def step_add_segment_video_filters(segment, segment_index, raw_label)
    output_label = "foreground_#{segment_index}"
    filters = [
      "trim=start=#{decimal(segment.fetch('start_seconds'))}:end=#{decimal(segment.fetch('end_seconds'))}",
      "setpts=(PTS-STARTPTS)/#{decimal(segment.fetch('speed'))}",
      "fps=#{frame_rate}",
      "scale=#{width}:#{height}:force_original_aspect_ratio=#{@edit_config.dig('canvas', 'mode') == 'fit' ? 'decrease' : 'increase'}:flags=lanczos"
    ]
    if @edit_config.dig("canvas", "mode") == "fit"
      filters.concat([ "format=rgba", "pad=#{width}:#{height}:(ow-iw)/2:(oh-ih)/2:color=black@0", "setsar=1" ])
    else
      filters.concat([ "crop=#{width}:#{height}", "setsar=1", "format=rgba" ])
    end
    @filter_chains << "[#{raw_label}]#{filters.join(',')}[#{output_label}]"
  end

  def step_add_blur_background_filters(segment, segment_index, raw_label)
    output_label = "blur_background_#{segment_index}"
    filters = [
      "trim=start=#{decimal(segment.fetch('start_seconds'))}:end=#{decimal(segment.fetch('end_seconds'))}",
      "setpts=(PTS-STARTPTS)/#{decimal(segment.fetch('speed'))}",
      "fps=#{frame_rate}",
      "scale=#{width}:#{height}:force_original_aspect_ratio=increase:flags=lanczos",
      "crop=#{width}:#{height}",
      "boxblur=20:10",
      "setsar=1",
      "format=rgba"
    ]
    @filter_chains << "[#{raw_label}]#{filters.join(',')}[#{output_label}]"
  end

  def step_add_segment_concat(segment_count)
    labels = segment_count.times.map { |segment_index| "[foreground_#{segment_index}]" }.join
    @filter_chains << "#{labels}concat=n=#{segment_count}:v=1:a=0[foreground_video]"
  end

  def step_add_blur_background_concat(segment_count)
    labels = segment_count.times.map { |segment_index| "[blur_background_#{segment_index}]" }.join
    @filter_chains << "#{labels}concat=n=#{segment_count}:v=1:a=0[canvas_background]"
  end

  def step_build_audio_filters
    @audio_enabled = @render_version.source_asset.media_metadata.fetch("has_audio", false) &&
      @edit_config.fetch("segments").any? { |segment| segment.fetch("audio_mode") == "keep" }
    return unless @audio_enabled

    kept_segments = @edit_config.fetch("segments").each_index.select do |segment_index|
      @edit_config.fetch("segments").fetch(segment_index).fetch("audio_mode") == "keep"
    end
    raw_labels = step_split_audio(kept_segments.length)
    kept_label_index = 0

    @edit_config.fetch("segments").each_with_index do |segment, segment_index|
      if segment.fetch("audio_mode") == "keep"
        step_add_kept_audio_filters(segment, segment_index, raw_labels.fetch(kept_label_index))
        kept_label_index += 1
      else
        step_add_silent_audio_filters(segment, segment_index)
      end
    end

    labels = @edit_config.fetch("segments").each_index.map { |segment_index| "[audio_#{segment_index}]" }.join
    @filter_chains << "#{labels}concat=n=#{@edit_config.fetch('segments').length}:v=0:a=1[audio_output]"
  end

  def step_split_audio(split_count)
    labels = split_count.times.map { |label_index| "audio_source_#{label_index}" }
    outputs = labels.map { |label| "[#{label}]" }.join
    @filter_chains << "[0:a]asplit=#{split_count}#{outputs}"
    labels
  end

  def step_add_kept_audio_filters(segment, segment_index, raw_label)
    duration = (segment.fetch("end_seconds") - segment.fetch("start_seconds")) / segment.fetch("speed")
    filters = [
      "atrim=start=#{decimal(segment.fetch('start_seconds'))}:end=#{decimal(segment.fetch('end_seconds'))}",
      "asetpts=PTS-STARTPTS",
      "atempo=#{decimal(segment.fetch('speed'))}",
      "volume=#{decimal(segment.fetch('audio_volume'))}",
      "aresample=48000",
      "atrim=duration=#{decimal(duration)}",
      "asetpts=PTS-STARTPTS"
    ]
    @filter_chains << "[#{raw_label}]#{filters.join(',')}[audio_#{segment_index}]"
  end

  def step_add_silent_audio_filters(segment, segment_index)
    duration = (segment.fetch("end_seconds") - segment.fetch("start_seconds")) / segment.fetch("speed")
    @filter_chains << "anullsrc=r=48000:cl=stereo,atrim=duration=#{decimal(duration)},asetpts=PTS-STARTPTS[audio_#{segment_index}]"
  end

  def step_build_composition_filters
    step_add_canvas_background
    @filter_chains << "[canvas_background][foreground_video]overlay=0:0:shortest=1[composed_video]"

    filters = []
    filters << "eq=brightness=#{decimal(@edit_config.dig('filters', 'brightness'))}:contrast=#{decimal(@edit_config.dig('filters', 'contrast'))}"
    filters << "format=yuv420p"
    @filter_chains << "[composed_video]#{filters.join(',')}[filtered_video]"
  end

  def step_add_canvas_background
    background = @edit_config.dig("canvas", "background")

    case background.fetch("type")
    when "color"
      duration = decimal(output_duration)
      color = "0x#{background.fetch('color').delete_prefix('#')}"
      @filter_chains << "color=c=#{color}:s=#{width}x#{height}:r=#{frame_rate}:d=#{duration},format=rgba[canvas_background]"
    when "image"
      input_index = @background_input_index
      step_add_background_input_filters(input_index, output_duration)
    when "video"
      input_index = @background_input_index
      step_add_background_input_filters(input_index, output_duration)
    end
  end

  def step_add_background_input_filters(input_index, duration)
    filters = [
      "trim=duration=#{decimal(duration)}",
      "setpts=PTS-STARTPTS",
      "fps=#{frame_rate}",
      "scale=#{width}:#{height}:force_original_aspect_ratio=increase:flags=lanczos",
      "crop=#{width}:#{height}",
      "setsar=1",
      "format=rgba"
    ]
    @filter_chains << "[#{input_index}:v]#{filters.join(',')}[canvas_background]"
  end

  def step_build_overlay_filters
    previous_label = "filtered_video"

    @edit_config.fetch("overlays").each_with_index do |overlay, overlay_index|
      output_label = "overlay_video_#{overlay_index}"
      if overlay.fetch("type") == "logo"
        step_add_logo_overlay(overlay, overlay_index, previous_label, output_label)
      else
        step_add_text_overlay(overlay, overlay_index, previous_label, output_label)
      end
      previous_label = output_label
    end

    @final_video_label = previous_label
  end

  def step_add_logo_overlay(overlay, overlay_index, previous_label, output_label)
    input_index = @logo_input_indices.fetch(overlay_index)
    overlay_label = "logo_#{overlay_index}"
    overlay_width = (overlay.fetch("width") * width).round.clamp(1, width)
    overlay_height = (overlay.fetch("height") * height).round.clamp(1, height)
    opacity = decimal(overlay.fetch("opacity"))
    start_time = decimal(overlay.fetch("output_start_seconds"))
    end_time = decimal(overlay.fetch("output_end_seconds"))
    x = (overlay.fetch("x") * width).round
    y = (overlay.fetch("y") * height).round

    @filter_chains << "[#{input_index}:v]scale=#{overlay_width}:#{overlay_height},format=rgba,colorchannelmixer=aa=#{opacity}[#{overlay_label}]"
    @filter_chains << "[#{previous_label}][#{overlay_label}]overlay=x=#{x}:y=#{y}:eof_action=pass:enable='between(t,#{start_time},#{end_time})'[#{output_label}]"
  end

  def step_add_text_overlay(overlay, overlay_index, previous_label, output_label)
    text_path = File.join(@temporary_directory, "overlay-#{overlay_index}.txt")
    File.write(text_path, overlay.fetch("text"), mode: "w:UTF-8")
    text_width = (overlay.fetch("width") * width).round
    text_height = (overlay.fetch("height") * height).round
    font_size = [ (text_height * (overlay.fetch("type") == "subtitle" ? 0.45 : 0.65)).round, 16 ].max
    x = (overlay.fetch("x") * width).round
    y = (overlay.fetch("y") * height).round
    opacity = decimal(overlay.fetch("opacity"))
    start_time = decimal(overlay.fetch("output_start_seconds"))
    end_time = decimal(overlay.fetch("output_end_seconds"))
    font_file = escape_filter_path(MEDIA_CONFIGURATION.fetch(:ffmpeg_font_file))
    escaped_text_path = escape_filter_path(text_path)
    drawtext = "drawtext=fontfile='#{font_file}':textfile='#{escaped_text_path}':expansion=none:fontcolor=white@#{opacity}:fontsize=#{font_size}:x=#{x}+(#{text_width}-text_w)/2:y=#{y}+(#{text_height}-text_h)/2:box=1:boxcolor=black@0.45:boxborderw=8:fix_bounds=1:enable='between(t,#{start_time},#{end_time})'"
    @filter_chains << "[#{previous_label}]#{drawtext}[#{output_label}]"
  end

  def step_build_output_arguments(input_arguments)
    video_codec = PROFILE_CONFIGURATION.fetch(:video_codec)
    arguments = [
      "-nostdin", "-hide_banner", "-loglevel", "error", "-filter_complex_threads", thread_count.to_s,
      *input_arguments,
      "-filter_complex", @filter_chains.join(";"),
      "-map", "[#{@final_video_label}]",
      "-c:v", video_codec,
      "-preset", PROFILE_CONFIGURATION.fetch(:video_preset),
      "-crf", PROFILE_CONFIGURATION.fetch(:video_crf).to_s,
      "-pix_fmt", "yuv420p",
      "-r", frame_rate.to_s,
      "-threads", thread_count.to_s,
      "-movflags", "+faststart"
    ]
    arguments.concat([ "-map", "[audio_output]", "-c:a", PROFILE_CONFIGURATION.fetch(:audio_codec) ]) if @audio_enabled
    arguments.concat([ "-f", "mp4", "-n", @output_path ])
  end

  def output_duration
    @edit_config.fetch("segments").sum do |segment|
      (segment.fetch("end_seconds") - segment.fetch("start_seconds")) / segment.fetch("speed")
    end
  end

  def decimal(value)
    format("%.6f", value.to_f).sub(/0+\z/, "").sub(/\.\z/, "")
  end

  def escape_filter_path(path)
    path.to_s.gsub("\\", "\\\\").gsub(":", "\\:").gsub("'", "\\'")
  end

  def width
    PROFILE_CONFIGURATION.fetch(:width)
  end

  def height
    PROFILE_CONFIGURATION.fetch(:height)
  end

  def frame_rate
    PROFILE_CONFIGURATION.fetch(:frame_rate)
  end

  def thread_count
    MEDIA_CONFIGURATION.fetch(:ffmpeg_threads)
  end
end
