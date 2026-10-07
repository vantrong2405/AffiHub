class RenderVersions::EditConfigValidator < ApplicationService
  INVALID_CONFIGURATION_MESSAGE = "Cấu hình chỉnh sửa không hợp lệ. Hãy kiểm tra timeline, nền, lớp phủ và vùng gỡ logo."
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
  LIMIT_CONFIGURATION = CONFIGURATION.fetch(:limits)
  TOP_LEVEL_KEYS = %w[schema_version segments canvas filters overlays delogo_regions].freeze
  SEGMENT_KEYS = %w[start_seconds end_seconds speed audio_mode audio_volume].freeze
  CANVAS_KEYS = %w[mode background].freeze
  FILTER_KEYS = %w[brightness contrast].freeze
  OVERLAY_KEYS = %w[type output_start_seconds output_end_seconds x y width height opacity].freeze
  DELOGO_KEYS = %w[x y width height].freeze

  attr_reader :normalized_edit_config, :output_duration_seconds

  # Initializes validation for one source edit configuration.
  #
  # @param video_project [VideoProject] the project that owns all selected media
  # @param source_asset [SourceAsset] the ready source being edited
  # @param edit_config [Hash] schema version 1 edit configuration
  # @return [RenderVersions::EditConfigValidator] the configured validator
  def initialize(video_project:, source_asset:, edit_config:)
    @video_project = video_project
    @source_asset = source_asset
    @edit_config = edit_config
    super()
  end

  # Checks the edit schema, ranges, source dimensions, and project-owned references.
  #
  # @return [Boolean] whether the configuration can be saved and rendered
  def call
    return step_fail!(INVALID_CONFIGURATION_MESSAGE) unless valid_edit_config?

    @normalized_edit_config = @edit_config.deep_dup
    @output_duration_seconds = calculate_output_duration
    step_succeed!
    success?
  end

  private

  def valid_edit_config?
    return false unless @video_project&.persisted? && @source_asset&.ready?
    return false unless @source_asset.video_project_id == @video_project.id
    return false unless valid_source_metadata?
    return false unless @edit_config.is_a?(Hash) && keys_match?(@edit_config, TOP_LEVEL_KEYS)
    return false unless @edit_config["schema_version"] == 1
    return false unless valid_segments?
    return false unless valid_canvas?
    return false unless valid_filters?
    return false unless valid_overlays?

    valid_delogo_regions?
  end

  def valid_segments?
    segments = @edit_config["segments"]
    return false unless segments.is_a?(Array)
    return false unless segments.length.between?(1, LIMIT_CONFIGURATION.fetch(:render_segment_max_count))

    segments.all? do |segment|
      valid_segment?(segment)
    end
  end

  def valid_segment?(segment)
    return false unless keys_match?(segment, SEGMENT_KEYS)
    return false unless finite_number?(segment["start_seconds"]) && finite_number?(segment["end_seconds"])
    return false unless segment["start_seconds"] >= 0 && segment["end_seconds"] > segment["start_seconds"]
    return false unless segment["end_seconds"] <= source_duration
    return false unless [ 1, 1.0, 2, 2.0 ].include?(segment["speed"])
    return false unless %w[keep mute].include?(segment["audio_mode"])

    number_between?(segment["audio_volume"], 0, 2)
  end

  def valid_canvas?
    canvas = @edit_config["canvas"]
    return false unless keys_match?(canvas, CANVAS_KEYS)
    return false unless %w[fit crop].include?(canvas["mode"])

    valid_background?(canvas["background"])
  end

  def valid_background?(background)
    return false unless background.is_a?(Hash)

    case background["type"]
    when "blur"
      keys_match?(background, %w[type])
    when "color"
      keys_match?(background, %w[type color]) && background["color"].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)
    when "image"
      keys_match?(background, %w[type project_media_asset_id]) && project_image_exists?(background["project_media_asset_id"])
    when "video"
      keys_match?(background, %w[type source_asset_id]) && ready_project_video_exists?(background["source_asset_id"])
    else
      false
    end
  end

  def valid_filters?
    filters = @edit_config["filters"]
    return false unless keys_match?(filters, FILTER_KEYS)

    number_between?(filters["brightness"], -1, 1) && number_between?(filters["contrast"], 0, 2)
  end

  def valid_overlays?
    overlays = @edit_config["overlays"]
    return false unless overlays.is_a?(Array)
    return false if overlays.length > LIMIT_CONFIGURATION.fetch(:render_overlay_max_count)

    overlays.all? do |overlay|
      valid_overlay?(overlay)
    end
  end

  def valid_overlay?(overlay)
    return false unless overlay.is_a?(Hash)

    case overlay["type"]
    when "text", "subtitle"
      valid_text_overlay?(overlay)
    when "logo"
      valid_logo_overlay?(overlay)
    else
      false
    end
  end

  def valid_text_overlay?(overlay)
    return false unless keys_match?(overlay, OVERLAY_KEYS + %w[text])
    return false unless overlay["text"].is_a?(String) && overlay["text"].present?
    return false if overlay["text"].length > LIMIT_CONFIGURATION.fetch(:render_text_max_characters)

    valid_overlay_timing_and_geometry?(overlay)
  end

  def valid_logo_overlay?(overlay)
    return false unless keys_match?(overlay, OVERLAY_KEYS + %w[project_media_asset_id])
    return false unless project_image_exists?(overlay["project_media_asset_id"])

    valid_overlay_timing_and_geometry?(overlay)
  end

  def valid_overlay_timing_and_geometry?(overlay)
    return false unless finite_number?(overlay["output_start_seconds"]) && finite_number?(overlay["output_end_seconds"])
    return false unless overlay["output_start_seconds"] >= 0
    return false unless overlay["output_end_seconds"] > overlay["output_start_seconds"]
    return false unless overlay["output_end_seconds"] <= calculate_output_duration
    return false unless number_between?(overlay["x"], 0, 1) && number_between?(overlay["y"], 0, 1)
    return false unless positive_number_at_most_one?(overlay["width"]) && positive_number_at_most_one?(overlay["height"])
    return false unless overlay["x"] + overlay["width"] <= 1 && overlay["y"] + overlay["height"] <= 1

    number_between?(overlay["opacity"], 0, 1)
  end

  def valid_delogo_regions?
    regions = @edit_config["delogo_regions"]
    return false unless regions.is_a?(Array)
    return false if regions.length > LIMIT_CONFIGURATION.fetch(:delogo_region_max_count)

    regions.all? do |region|
      valid_delogo_region?(region)
    end
  end

  def valid_delogo_region?(region)
    return false unless keys_match?(region, DELOGO_KEYS)
    return false unless DELOGO_KEYS.all? { |key| region[key].is_a?(Integer) }
    return false unless region["x"] >= 0 && region["y"] >= 0
    return false unless region["width"].positive? && region["height"].positive?

    region["x"] + region["width"] <= source_width && region["y"] + region["height"] <= source_height
  end

  def project_image_exists?(asset_id)
    return false unless asset_id.is_a?(Integer) && asset_id.positive?

    asset = @video_project.project_media_assets.find_by(id: asset_id)
    asset&.file&.attached? == true
  end

  def ready_project_video_exists?(asset_id)
    return false unless asset_id.is_a?(Integer) && asset_id.positive?

    SourceAsset.exists?(id: asset_id, video_project_id: @video_project.id, status: "ready")
  end

  def keys_match?(value, keys)
    value.is_a?(Hash) && value.keys.sort == keys.sort
  end

  def finite_number?(value)
    value.is_a?(Numeric) && value.finite?
  end

  def number_between?(value, minimum, maximum)
    finite_number?(value) && value.between?(minimum, maximum)
  end

  def positive_number_at_most_one?(value)
    finite_number?(value) && value.positive? && value <= 1
  end

  def calculate_output_duration
    @edit_config.fetch("segments").sum do |segment|
      (segment.fetch("end_seconds") - segment.fetch("start_seconds")) / segment.fetch("speed")
    end
  end

  def source_duration
    @source_asset.media_metadata.fetch("duration_seconds")
  end

  def valid_source_metadata?
    metadata = @source_asset.media_metadata
    metadata.is_a?(Hash) && finite_number?(metadata["duration_seconds"]) && metadata["duration_seconds"].positive? &&
      metadata["width"].is_a?(Integer) && metadata["width"].positive? &&
      metadata["height"].is_a?(Integer) && metadata["height"].positive?
  end

  def source_width
    @source_asset.media_metadata.fetch("width")
  end

  def source_height
    @source_asset.media_metadata.fetch("height")
  end
end
