class SourceAssets::ShowService < ApplicationService
  # @return [VideoProject] the project that owns the asset
  attr_reader :video_project

  # @return [SourceAsset] the selected project source
  attr_reader :source_asset

  # Initializes a source asset detail query.
  #
  # @param video_project_id [Integer] the owning project
  # @param source_asset_id [Integer] the source asset to display
  # @return [SourceAssets::ShowService] the configured service
  def initialize(video_project_id:, source_asset_id:)
    @video_project_id = video_project_id
    @source_asset_id = source_asset_id
    super()
  end

  # Loads only a source asset owned by the selected project.
  #
  # @return [Boolean] whether the source page was loaded
  def call
    step_load_video_project
    step_load_source_asset
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_load_source_asset
    @source_asset = video_project.source_assets.with_attached_file.find(@source_asset_id)
  end
end
