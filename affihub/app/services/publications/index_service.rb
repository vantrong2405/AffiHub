class Publications::IndexService < ApplicationService
  # The project whose Publication history is displayed.
  # @return [VideoProject]
  attr_reader :video_project

  # Recent Publication records belonging to the selected project.
  # @return [ActiveRecord::Relation<Publication>]
  attr_reader :publications

  # Initializes a Publication history query for one project.
  #
  # @param video_project_id [Integer] the project whose Publication history is requested
  # @return [Publications::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads the selected project and its recent publications.
  #
  # @return [Boolean] whether the history was loaded
  def call
    return false unless step_load_video_project

    step_load_publications
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
    true
  end

  def step_load_publications
    @publications = video_project.publications
      .includes(:social_destination, :render_version)
      .recent_first
  end
end
