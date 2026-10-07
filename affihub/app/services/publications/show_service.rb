class Publications::ShowService < ApplicationService
  # The project that owns the reviewed Publication.
  # @return [VideoProject]
  attr_reader :video_project

  # The Publication being reviewed.
  # @return [Publication]
  attr_reader :publication

  # The latest preflight report for the immutable render version.
  # @return [PreflightReport, nil]
  attr_reader :latest_preflight_report

  # Whether the latest report allows this destination to publish.
  # @return [Boolean]
  attr_reader :preflight_ready

  # The latest publish workflow for the Publication.
  # @return [WorkflowRun, nil]
  attr_reader :workflow_run

  # The latest outbound request attempt for the current workflow.
  # @return [OutboundAttempt, nil]
  attr_reader :outbound_attempt

  # Initializes review data for one Publication in a project.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the Publication to review
  # @return [Publications::ShowService] the configured service
  def initialize(video_project_id:, publication_id:)
    @video_project_id = video_project_id
    @publication_id = publication_id
    super()
  end

  # Loads the Publication and current preflight/workflow state.
  #
  # @return [Boolean] whether the review data was loaded
  def call
    return false unless step_load_video_project
    return false unless step_load_publication

    step_load_latest_preflight_report
    step_load_latest_workflow_run
    step_load_latest_outbound_attempt
    step_succeed!
    success?
  end

  private

  def step_load_video_project
    @video_project = VideoProject.find(@video_project_id)
    true
  end

  def step_load_publication
    @publication = Publication.where(id: video_project.publications.select(:id))
      .includes(:social_destination, :render_version)
      .find(@publication_id)
    true
  end

  def step_load_latest_preflight_report
    @latest_preflight_report = publication.render_version.preflight_reports.recent_first.first
    @preflight_ready = latest_preflight_report&.ready_for?(
      render_version: publication.render_version,
      social_destination: publication.social_destination
    ) || false
  end

  def step_load_latest_workflow_run
    @workflow_run = publication.workflow_runs.order(created_at: :desc, id: :desc).first
  end

  def step_load_latest_outbound_attempt
    @outbound_attempt = workflow_run&.outbound_attempts&.order(attempt_number: :desc)&.first
  end
end
