class DriveExports::IndexService < ApplicationService
  # The project whose local Drive export history is shown.
  # @return [VideoProject, nil]
  attr_reader :video_project

  # The project-scoped Drive export statuses.
  # @return [Array<DriveExport>]
  attr_reader :drive_exports

  # Connected Drive accounts available for a new export.
  # @return [Array<GoogleConnection>]
  attr_reader :google_connections

  # Ready render versions that can be uploaded manually from this page.
  # @return [Array<RenderVersion>]
  attr_reader :render_versions

  # Reports whether the project has any Drive export history.
  # @return [Boolean]
  attr_reader :has_drive_exports

  # Reports whether a connected Drive account is available for a new export.
  # @return [Boolean]
  attr_reader :has_drive_connections

  # Reports whether the manual export form can be shown.
  # @return [Boolean]
  attr_reader :has_export_form

  # The default connected account selected for the export form.
  # @return [Integer, nil]
  attr_reader :default_google_connection_id

  # Initializes the project-scoped Drive export list.
  #
  # @param video_project_id [Integer] the owning project
  # @return [DriveExports::IndexService] the configured service
  def initialize(video_project_id:)
    @video_project_id = video_project_id
    super()
  end

  # Loads Drive statuses and available connected accounts for one project.
  #
  # @return [Boolean] whether the export list was loaded
  def call
    return false unless step_load_project

    step_load_drive_exports
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

  def step_load_drive_exports
    @drive_exports = DriveExport.joins(:render_version)
      .where(render_versions: { video_project_id: video_project.id })
      .includes(:google_connection, :render_version)
      .order(updated_at: :desc, id: :desc)
      .to_a
    @has_drive_exports = drive_exports.any?
  end

  def step_load_google_connections
    @google_connections = GoogleConnection.connected.where(integration: "drive").order(:email).to_a
    @has_drive_connections = google_connections.any?
    @default_google_connection_id = google_connections.first&.id
  end

  def step_load_render_versions
    @render_versions = video_project.render_versions.ready.with_attached_file.order(created_at: :desc, id: :desc)
      .select { |render_version| render_version.file.attached? }
    @has_export_form = has_drive_connections && render_versions.any?
  end
end
