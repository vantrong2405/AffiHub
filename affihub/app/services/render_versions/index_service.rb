class RenderVersions::IndexService < ApplicationService
  # @return [VideoProject] the project whose renders are listed
  attr_reader :video_project

  # @return [Array<RenderVersion>] the project's renders, newest first
  attr_reader :render_versions

  # Initializes a render history query for one project.
  #
  # @param video_project_id [Integer] the project to display
  # @return [RenderVersions::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the render history for the selected project.
  #
  # @return [Boolean] whether the render history was loaded
  def call
    @video_project = VideoProject.find(@video_project_id)
    @render_versions = video_project.render_versions.with_attached_file.recent_first.to_a
    step_succeed!
    success?
  end
end
