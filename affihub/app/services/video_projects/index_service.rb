class VideoProjects::IndexService < ApplicationService
  # @return [Array<VideoProject>] the projects available in the workspace
  attr_reader :video_projects

  # Initializes the project index query.
  #
  # @return [VideoProjects::IndexService] the configured service
  def initialize
    super()
  end

  # Loads projects in their display order.
  #
  # @return [Boolean] whether the project list was loaded
  def call
    step_load_video_projects
    step_succeed!
    success?
  end

  private

  def step_load_video_projects
    @video_projects = VideoProject.ordered_by_name.to_a
  end
end
