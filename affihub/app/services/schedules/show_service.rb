class Schedules::ShowService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow)
    .deep_symbolize_keys
    .fetch(:publication_quota)

  attr_reader :video_project, :schedule, :occurrences, :quota_summary

  # Initializes the Schedule detail query for one project.
  #
  # @param video_project_id [Integer] the project that owns the Schedule
  # @param schedule_id [Integer] the Schedule to display
  # @return [Schedules::ShowService] the configured service
  def initialize(video_project_id:, schedule_id:)
    @video_project_id = video_project_id
    @schedule_id = schedule_id
    super()
  end

  # Loads Schedule history and current quota availability for each destination.
  #
  # @return [Boolean] whether the Schedule detail was loaded
  def call
    return false unless step_load_schedule

    step_load_occurrences
    step_build_quota_summary
    step_succeed!
    success?
  end

  private

  def step_load_schedule
    @video_project = VideoProject.find(@video_project_id)
    @schedule = Schedule.joins(:render_version)
      .where(render_versions: { video_project_id: video_project.id })
      .includes(:render_version, schedule_destinations: :social_destination)
      .find(@schedule_id)
    true
  end

  def step_load_occurrences
    @occurrences = schedule.schedule_occurrences
      .includes(publications: :social_destination)
      .order(scheduled_at: :desc, id: :desc)
      .to_a
  end

  def step_build_quota_summary
    @quota_summary = schedule.schedule_destinations.includes(:social_destination).order(:id).map do |schedule_destination|
      reservations = step_active_reservations(schedule_destination.social_destination)
      {
        social_destination_id: schedule_destination.social_destination_id,
        social_destination: schedule_destination.social_destination,
        used: reservations.size,
        limit: max_per_destination,
        next_available_at: step_next_available_at(reservations)
      }
    end
  end

  def step_active_reservations(social_destination)
    window_start = Time.current - window_seconds.seconds
    PublicationQuotaReservation.where(social_destination:)
      .where(reserved_at: window_start...Time.current)
      .order(:reserved_at, :id)
      .to_a
  end

  def step_next_available_at(reservations)
    return if reservations.size < max_per_destination

    reservations[reservations.size - max_per_destination].reserved_at + window_seconds.seconds
  end

  def max_per_destination
    CONFIGURATION.fetch(:max_per_destination).to_i
  end

  def window_seconds
    CONFIGURATION.fetch(:window_seconds).to_i
  end
end
