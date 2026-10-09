class SheetSyncsController < MainController
  # Lists this project's current Sheets rows and explicit backfill choices.
  #
  # @return [ActionController::Metal::Response] the project sync index response
  def index
    service = SheetSyncs::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    return render_service(service, failure_redirect: video_projects_path) unless service.success?

    @video_project = service.video_project
    @sheet_syncs = service.sheet_syncs
    @google_connections = service.google_connections
    @render_versions = service.render_versions
    @has_sheet_syncs = service.has_sheet_syncs
    @has_google_connections = service.has_google_connections
    @has_backfill_form = service.has_backfill_form
    @default_google_connection_id = service.default_google_connection_id
  end

  # Shows one row's current Sheets sync and local Publication state.
  #
  # @return [ActionController::Metal::Response] the sync status response
  def show
    service = SheetSyncs::ShowService.new(
      video_project_id: params[:video_project_id],
      sheet_sync_id: params[:id]
    )
    service.call
    return render_service(service, failure_redirect: video_project_path(params[:video_project_id])) unless service.success?

    @video_project = service.video_project
    @sheet_sync = service.sheet_sync
    @publication = service.publication
    @can_retry = service.can_retry
    @has_safe_error = service.has_safe_error
    @safe_error_code = service.safe_error_code
    @outcome_unknown = service.outcome_unknown
    @has_publication = service.has_publication
    @has_publication_error = service.has_publication_error
  end

  # Queues Sheets rows only for render versions explicitly selected by the user.
  #
  # @return [ActionController::Metal::Response] the selected backfill response
  def create
    service = SheetSyncs::BackfillService.new(
      google_connection_id: params[:google_connection_id],
      video_project_id: params[:video_project_id],
      render_version_ids: params[:render_version_ids]
    )
    service.call

    render_service(
      service,
      success: video_project_sheet_syncs_path(params[:video_project_id]),
      failure_redirect: video_project_sheet_syncs_path(params[:video_project_id]),
      notice: "Đã xếp hàng các bản render đã chọn để đồng bộ Sheets."
    )
  end
end
