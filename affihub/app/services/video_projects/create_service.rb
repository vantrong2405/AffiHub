class VideoProjects::CreateService < ApplicationService
  # @return [VideoProject] the project created by the service
  attr_reader :video_project

  # Initializes project creation from the submitted name.
  #
  # @param name [String] the project name
  # @return [VideoProjects::CreateService] the configured service
  def initialize(name:)
    @name = name
    super()
  end

  # Persists a new project when its name is valid.
  #
  # @return [Boolean] whether the project was created
  def call
    return false unless step_create_video_project

    step_succeed!
    success?
  end

  private

  def step_create_video_project
    @video_project = VideoProject.new(name: @name)
    return true if video_project.save

    step_fail!(video_project.errors.full_messages.to_sentence)
  end
end
