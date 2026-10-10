class VideoProjects::EditService < ApplicationService
  # @return [VideoProject] the selected project
  attr_reader :video_project

  # Initializes a project edit query.
  #
  # @param video_project_id [Integer] the project to edit
  # @return [VideoProjects::EditService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the project used by the edit form.
  #
  # @return [Boolean] whether the project was loaded
  def call
    step_load_video_project
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
  end
end
