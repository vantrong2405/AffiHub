class RenderVersions::ShowService < ApplicationService
  # @return [VideoProject] the project that owns the render
  attr_reader :video_project

  # @return [RenderVersion] the selected render version
  attr_reader :render_version

  # @return [SourceAsset] the source used by the render
  attr_reader :source_asset

  # Initializes a render detail query scoped to one project.
  #
  # @param video_project_id [Integer] the project that owns the render
  # @param render_version_id [Integer] the render version to display
  # @return [RenderVersions::ShowService] the configured service
  def initialize(video_project_id:, render_version_id:)
    @video_project_id = video_project_id
    @render_version_id = render_version_id
    super()
  end

  # Loads one render and its source from the selected project.
  #
  # @return [Boolean] whether the render page was loaded
  def call
    @video_project = VideoProject.find(@video_project_id)
    @render_version = video_project.render_versions.with_attached_file.includes(:source_asset).find(@render_version_id)
    @source_asset = render_version.source_asset
    step_succeed!
    success?
  end
end
