class RenderVersions::NewService < ApplicationService
  # @return [VideoProject] the project being edited
  attr_reader :video_project

  # @return [Array<SourceAsset>] ready sources available to the editor
  attr_reader :source_assets

  # @return [SourceAsset, nil] the selected ready source
  attr_reader :selected_source_asset

  # @return [Array<ProjectMediaAsset>] images available to the editor
  attr_reader :project_media_assets

  # @return [Hash] the starting edit configuration
  attr_reader :edit_config

  # Initializes the editor form for one project and optional source.
  #
  # @param video_project_id [Integer] the project to edit
  # @param source_asset_id [Integer, nil] an optional source selected from the project
  # @return [RenderVersions::NewService] the configured service
  def initialize(video_project_id:, source_asset_id: nil)
    @video_project_id = video_project_id
    @source_asset_id = source_asset_id
    super()
  end

  # Loads the project media needed to render a new version.
  #
  # @return [Boolean] whether the editor form data was loaded
  def call
    @video_project = VideoProject.find(@video_project_id)
    @source_assets = video_project.source_assets.ready.with_attached_file.recent_first.to_a
    @selected_source_asset = selected_source
    return step_fail!("Chỉ có thể chọn source sẵn sàng trong project hiện tại.") if @source_asset_id.present? && selected_source_asset.nil?

    @project_media_assets = video_project.project_media_assets.with_attached_file.order(created_at: :desc, id: :desc).to_a
    @edit_config = default_edit_config
    step_succeed!
    success?
  end

  private

  def selected_source
    return source_assets.first if @source_asset_id.blank?

    source_assets.find { |source_asset| source_asset.id.to_s == @source_asset_id.to_s }
  end

  def default_edit_config
    {
      "schema_version" => 1,
      "segments" => [
        {
          "start_seconds" => 0.0,
          "end_seconds" => selected_source_duration,
          "speed" => 1.0,
          "audio_mode" => "keep",
          "audio_volume" => 1.0
        }
      ],
      "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
      "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
      "overlays" => [],
      "delogo_regions" => []
    }
  end

  def selected_source_duration
    return 1.0 if selected_source_asset.blank?

    duration = Float(selected_source_asset.media_metadata.fetch("duration_seconds", 1.0))
    duration.finite? && duration.positive? ? duration : 1.0
  rescue ArgumentError, TypeError
    1.0
  end
end
