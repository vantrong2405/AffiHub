class VideoProjects::NewService < ApplicationService
  # @return [VideoProject] the unsaved project for the form
  attr_reader :video_project

  # Initializes a new project form service.
  #
  # @return [VideoProjects::NewService] the configured service
  def initialize
    super()
  end

  # Builds an unsaved project for the new form.
  #
  # @return [Boolean] whether the form project was built
  def call
    step_build_video_project
    step_succeed!
    success?
  end

  private

  def step_build_video_project
    @video_project = VideoProject.new
  end
end
