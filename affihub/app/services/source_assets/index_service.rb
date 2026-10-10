class SourceAssets::IndexService < ApplicationService
  # @return [VideoProject] the project that owns the asset list
  attr_reader :video_project

  # @return [Array<SourceAsset>] the project's source assets
  attr_reader :source_assets

  # Initializes a source asset list query.
  #
  # @param video_project_id [Integer] the owning project
  # @return [SourceAssets::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads source assets belonging to the selected project.
  #
  # @return [Boolean] whether the list was loaded
  def call
    step_load_video_project
    step_load_source_assets
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end

  def step_load_source_assets
    @source_assets = video_project.source_assets.with_attached_file.recent_first.to_a
  end
end
