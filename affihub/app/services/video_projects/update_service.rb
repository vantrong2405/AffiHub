class VideoProjects::UpdateService < ApplicationService
  # @return [VideoProject] the updated project
  attr_reader :video_project

  # Initializes a project update from the submitted values.
  #
  # @param video_project_id [Integer] the project to update
  # @param name [String] the new project name
  # @return [VideoProjects::UpdateService] the configured service
  def initialize(video_project_id:, name:)
    @video_project_id = video_project_id
    @name = name
    super()
  end

  # Updates the project name when it is valid.
  #
  # @return [Boolean] whether the project was updated
  def call
    return false unless step_update_video_project

    step_succeed!
    success?
  end

  private

  def step_update_video_project
    @video_project = VideoProject.find(@video_project_id)
    return true if video_project.update(name: @name)

    step_fail!(video_project.errors.full_messages.to_sentence)
  end
end
