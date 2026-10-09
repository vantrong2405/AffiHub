class DriveExportsController < MainController
  # Lists Drive export statuses belonging to one video project.
  #
  # @return [ActionController::Metal::Response] the project export index response
  def index
    service = DriveExports::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    return render_service(service, failure_redirect: video_projects_path) unless service.success?

    @video_project = service.video_project
    @drive_exports = service.drive_exports
    @google_connections = service.google_connections
    @render_versions = service.render_versions
    @has_drive_exports = service.has_drive_exports
    @has_drive_connections = service.has_drive_connections
    @has_export_form = service.has_export_form
    @default_google_connection_id = service.default_google_connection_id
  end

  # Requests a background upload of one ready render version to Google Drive.
  #
  # @return [ActionController::Metal::Response] the Drive export redirect response
  def create
    service = DriveExports::CreateService.new(
      video_project_id: params[:video_project_id],
      render_version_id: params[:render_version_id],
      google_connection_id: params[:google_connection_id]
    )
    service.call
    return render_service(service, failure_redirect: video_project_path(params[:video_project_id])) unless service.success?

    render_service(
      service,
      success: video_project_drive_export_path(service.video_project, service.drive_export),
      notice: "Đã xếp hàng lưu bản render lên Google Drive."
    )
  end

  # Shows one project's Drive upload status and safe reconciliation options.
  #
  # @return [ActionController::Metal::Response] the export status response
  def show
    service = DriveExports::ShowService.new(
      video_project_id: params[:video_project_id],
      drive_export_id: params[:id]
    )
    service.call
    return render_service(service, failure_redirect: video_project_path(params[:video_project_id])) unless service.success?

    @video_project = service.video_project
    @drive_export = service.drive_export
    @needs_manual_reconciliation = service.needs_manual_reconciliation
    @drive_url = service.drive_url
    @has_drive_url = service.has_drive_url
    @has_safe_error = service.has_safe_error
  end

  # Saves an explicit manual result for an uncertain Drive upload.
  #
  # @return [ActionController::Metal::Response] the reconciliation response
  def update
    service = DriveExports::UpdateService.new(
      video_project_id: params[:video_project_id],
      drive_export_id: params[:id],
      decision: params[:decision],
      evidence: params[:evidence],
      actor_reference: params[:actor_reference],
      provider_reference: params[:provider_reference],
      risk_confirmed: params[:risk_confirmed]
    )
    service.call

    render_service(
      service,
      success: video_project_drive_export_path(params[:video_project_id], params[:id]),
      failure_redirect: video_project_drive_export_path(params[:video_project_id], params[:id]),
      notice: "Đã lưu kết quả đối soát Drive."
    )
  end
end
