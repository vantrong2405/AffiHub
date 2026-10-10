class Schedules::IndexService < ApplicationService
  attr_reader :video_project, :schedules

  # Initializes the Schedule list query for one project.
  #
  # @param video_project_id [Integer] the project whose schedules are requested
  # @return [Schedules::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads project schedules in their next-occurrence order.
  #
  # @return [Boolean] whether the Schedule list was loaded
  def call
    return false unless step_load_video_project

    step_load_schedules
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
    true
  end

  def step_load_schedules
    @schedules = Schedule.joins(:render_version)
      .where(render_versions: { video_project_id: video_project.id })
      .includes(:render_version, schedule_destinations: :social_destination)
      .order(:next_occurrence_at, :id)
      .to_a
  end
end
