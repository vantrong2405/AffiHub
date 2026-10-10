class VideoProjects::DestroyService < ApplicationService
  # @return [VideoProject] the project being deleted
  attr_reader :video_project

  # Initializes deletion for one project.
  #
  # @param video_project_id [Integer] the project to delete
  # @return [VideoProjects::DestroyService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Deletes the project only when no retained media depends on it.
  #
  # @return [Boolean] whether the project was deleted
  def call
    return false unless step_destroy_video_project

    step_succeed!
    success?
  end

  private

  def step_destroy_video_project
    @video_project = VideoProject.find(@video_project_id)
    return true if video_project.destroy

    step_fail!(video_project.errors.full_messages.to_sentence)
  end
end
