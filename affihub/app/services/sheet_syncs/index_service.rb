class SheetSyncs::IndexService < ApplicationService
  # The project whose sync history and backfill choices are shown.
  # @return [VideoProject, nil]
  attr_reader :video_project

  # The project-scoped Sheets sync rows.
  # @return [Array<SheetSync>]
  attr_reader :sheet_syncs

  # Connected Sheets accounts with a saved document and worksheet.
  # @return [Array<GoogleConnection>]
  attr_reader :google_connections

  # Render versions that already have publication history for backfill.
  # @return [Array<RenderVersion>]
  attr_reader :render_versions

  # Reports whether sync history exists for the selected project.
  # @return [Boolean]
  attr_reader :has_sheet_syncs

  # Reports whether a configured Sheets account is available for backfill.
  # @return [Boolean]
  attr_reader :has_google_connections

  # Reports whether the explicit backfill form can be shown.
  # @return [Boolean]
  attr_reader :has_backfill_form

  # The default connected account selected for explicit backfill.
  # @return [Integer, nil]
  attr_reader :default_google_connection_id

  # Initializes the project-scoped Sheets list and backfill form.
  #
  # @param video_project_id [Integer] the project chosen for sync
  # @return [SheetSyncs::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads only this project's sync history and renders with publication history.
  #
  # @return [Boolean] whether the sync page was loaded
  def call
    return false unless step_load_project

    step_load_sheet_syncs
    step_load_google_connections
    step_load_render_versions
    step_succeed!
    success?
  end

  private

  def step_load_project
    @video_project = VideoProject.find_by(id: @video_project_id)
    return true if video_project

    step_fail!("Không tìm thấy project video.")
  end

  def step_load_sheet_syncs
    @sheet_syncs = SheetSync.joins(:render_version)
      .where(render_versions: { video_project_id: video_project.id })
      .includes(:google_connection, :social_destination, :render_version)
      .order(updated_at: :desc, id: :desc)
      .to_a
    @has_sheet_syncs = sheet_syncs.any?
  end

  def step_load_google_connections
    @google_connections = GoogleConnection.connected
      .where(integration: "sheets")
      .where.not(spreadsheet_id: nil)
      .where.not(worksheet_title: nil)
      .order(:email)
      .to_a
    @has_google_connections = google_connections.any?
    @default_google_connection_id = google_connections.first&.id
  end

  def step_load_render_versions
    @render_versions = video_project.render_versions.joins(:publications)
      .distinct
      .order(created_at: :desc, id: :desc)
      .to_a
    @has_backfill_form = has_google_connections && render_versions.any?
  end
end
