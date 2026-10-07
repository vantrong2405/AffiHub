class SourceAssets::NewService < ApplicationService
  # @return [VideoProject] the project receiving the upload
  attr_reader :video_project

  # Initializes a local upload form query.
  #
  # @param video_project_id [Integer] the owning project
  # @return [SourceAssets::NewService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the project for the local upload form.
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
