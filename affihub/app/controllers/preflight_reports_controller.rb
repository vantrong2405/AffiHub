class PreflightReportsController < MainController
  # Persists a read-only preflight report for the selected render and destinations.
  def create
    form_params = preflight_report_params
    service = PreflightReports::CreateService.new(
      video_project_id: params[:video_project_id],
      render_version_id: form_params[:render_version_id],
      social_destination_ids: form_params[:social_destination_ids]
    )
    service.call

    render_service(
      service,
      failure_redirect: video_project_render_version_path(service.video_project, service.render_version),
      notice: "Đã hoàn tất Kiểm tra toàn bộ."
    ) do
      video_project_preflight_report_path(service.video_project, service.preflight_report)
    end
  end

  # Loads the saved preflight report, destination filter, and comparison frames.
  def show
    service = PreflightReports::ShowService.new(
      video_project_id: params[:video_project_id],
      preflight_report_id: params[:id],
      destination_id: params[:destination_id]
    )
    raise ActiveRecord::RecordNotFound unless service.call

    @video_project = service.video_project
    @preflight_report = service.preflight_report
    @render_version = service.render_version
    @project_checks = service.project_checks
    @destination_entries = service.destination_entries
    @displayed_destination_entries = service.displayed_destination_entries
    @selected_destination_id = service.selected_destination_id
    @frame_strip = service.frame_strip
    @frame_error = service.frame_error
  end

  private

  def preflight_report_params
    params.require(:preflight_report).permit(:render_version_id, social_destination_ids: [])
  end
end
