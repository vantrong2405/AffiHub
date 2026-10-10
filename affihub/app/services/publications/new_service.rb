class Publications::NewService < ApplicationService
  # The project where the operator is creating drafts.
  # @return [VideoProject]
  attr_reader :video_project

  # Ready render versions' preflight reports for this project.
  # @return [ActiveRecord::Relation<PreflightReport>]
  attr_reader :preflight_reports

  # The report selected to build destination choices.
  # @return [PreflightReport, nil]
  attr_reader :preflight_report

  # The immutable render version covered by the selected report.
  # @return [RenderVersion, nil]
  attr_reader :render_version

  # Destinations that passed the selected report.
  # @return [Array<SocialDestination>]
  attr_reader :ready_social_destinations

  # Destinations that failed the selected report.
  # @return [Array<SocialDestination>]
  attr_reader :blocked_social_destinations

  # Initializes the Publication form data for one project.
  #
  # @param video_project_id [Integer] the project that owns candidate renders
  # @param preflight_report_id [Integer, nil] the report selected for draft creation
  # @return [Publications::NewService] the configured service
  def initialize(video_project_id:, preflight_report_id: nil)
    @video_project_id = video_project_id
    @preflight_report_id = preflight_report_id
    @ready_social_destinations = []
    @blocked_social_destinations = []
    super()
  end

  # Loads eligible reports and, when selected, their destination results.
  #
  # @return [Boolean] whether the form data was loaded
  def call
    return false unless step_load_video_project
    return false unless step_load_preflight_reports
    return false unless step_load_selected_preflight_report

    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
    true
  end

  def step_load_preflight_reports
    @preflight_reports = PreflightReport.joins(:render_version)
      .where(render_versions: { video_project_id: video_project.id, status: :ready })
      .includes(:render_version)
      .recent_first
    true
  end

  def step_load_selected_preflight_report
    return true if @preflight_report_id.blank?

    @preflight_report = preflight_reports.find(@preflight_report_id)

    @render_version = preflight_report.render_version
    step_load_destinations
  end

  def step_load_destinations
    social_destinations = SocialDestination.where(id: preflight_report.checked_destination_ids)
      .includes(:social_connection)
      .order(:name, :id)

    social_destinations.each do |social_destination|
      if preflight_report.ready_for?(render_version:, social_destination:)
        ready_social_destinations << social_destination
      else
        blocked_social_destinations << social_destination
      end
    end
    true
  end
end
