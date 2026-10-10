class DriveExports::ShowService < ApplicationService
  # The project that owns the Drive export.
  # @return [VideoProject, nil]
  attr_reader :video_project

  # The selected project-scoped Drive export.
  # @return [DriveExport, nil]
  attr_reader :drive_export

  # Reports whether the upload needs explicit manual reconciliation.
  # @return [Boolean]
  attr_reader :needs_manual_reconciliation

  # The safely stored Drive URL when the upload is known to have completed.
  # @return [String, nil]
  attr_reader :drive_url

  # Reports whether a Drive file URL can be displayed.
  # @return [Boolean]
  attr_reader :has_drive_url

  # Reports whether a safe error code is available for display.
  # @return [Boolean]
  attr_reader :has_safe_error

  # Initializes one Drive export status page.
  #
  # @param video_project_id [Integer] the owning project
  # @param drive_export_id [Integer] the selected export
  # @return [DriveExports::ShowService] the configured service
  def initialize(video_project_id:, drive_export_id:)
    @video_project_id = video_project_id
    @drive_export_id = drive_export_id
    @has_drive_url = false
    @has_safe_error = false
    super()
  end

  # Loads only an export owned by the selected project.
  #
  # @return [Boolean] whether the export was found
  def call
    return false unless step_load_project
    return false unless step_load_drive_export

    @needs_manual_reconciliation = drive_export.outcome_unknown?
    @drive_url = drive_export.drive_url
    @has_drive_url = drive_url.present?
    @has_safe_error = drive_export.safe_error_code.present?
    step_succeed!
    success?
  end

  private

  def step_load_project
    @video_project = VideoProject.find_by(id: @video_project_id)
    return true if video_project

    step_fail!("Không tìm thấy project video.")
  end

  def step_load_drive_export
    @drive_export = DriveExport.joins(:render_version)
      .includes(:google_connection, :render_version)
      .find_by(id: @drive_export_id, render_versions: { video_project_id: video_project.id })
    return true if drive_export

    step_fail!("Không tìm thấy bản xuất Drive trong project này.")
  end
end
