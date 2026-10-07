class PublicationsController < MainController
  # Lists Publication drafts and results for one project.
  def index
    service = Publications::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
    @publications = service.publications
  end

  # Loads the report and destination choices for creating draft Publications.
  def new
    load_new_form
  end

  # Creates one draft per selected ready destination.
  def create
    @publication_form = Publications::CreateForm.new(publication_params)
    service = Publications::CreateService.new(
      video_project_id: params[:video_project_id],
      render_version_id: @publication_form.render_version_id,
      preflight_report_id: @publication_form.preflight_report_id,
      destination_captions: @publication_form.destination_captions_for_create
    )
    service.call

    load_new_form(@publication_form.preflight_report_id) unless service.success?
    render_service(service, failure: :new, notice: "Đã tạo bản nháp đăng.") do
      video_project_publications_path(params[:video_project_id])
    end
  end

  # Shows the selected Publication's render, destination, caption, and status.
  def show
    load_review
  end

  # Updates the caption while the Publication remains a draft.
  def update
    service = Publications::UpdateService.new(
      video_project_id: params[:video_project_id],
      publication_id: params[:id],
      caption: publication_params[:caption]
    )
    service.call

    load_review
    render_service(service, failure: :show, notice: "Đã cập nhật caption.") do
      video_project_publication_path(@video_project, @publication)
    end
  end

  # Confirms a draft against the latest report and queues its publish workflow.
  def confirm
    load_review
    service = Publications::ConfirmService.new(
      video_project_id: params[:video_project_id],
      publication_id: params[:id],
      preflight_report_id: @latest_preflight_report&.id
    )
    service.call

    load_review
    render_service(service, failure: :show, notice: "Đã xác nhận yêu cầu đăng.") do
      video_project_publication_path(@video_project, @publication)
    end
  end

  # Records the operator's manual decision for an unresolved publish outcome.
  def resolve_outcome
    service = Publications::ResolveOutcomeService.new(
      video_project_id: params[:video_project_id],
      publication_id: params[:id],
      decision: publication_params[:decision],
      evidence: publication_params[:evidence],
      actor_reference: "local-operator",
      provider_reference: publication_params[:provider_reference],
      risk_confirmed: publication_params[:risk_confirmed] == "1"
    )
    service.call

    load_review
    render_service(service, failure: :show, notice: "Đã ghi nhận kết quả kiểm tra.") do
      video_project_publication_path(@video_project, @publication)
    end
  end

  private

  def load_new_form(preflight_report_id = params[:preflight_report_id])
    service = Publications::NewService.new(
      video_project_id: params[:video_project_id],
      preflight_report_id:
    )
    service.call
    @video_project = service.video_project
    @preflight_reports = service.preflight_reports
    @preflight_report = service.preflight_report
    @render_version = service.render_version
    @ready_social_destinations = service.ready_social_destinations
    @blocked_social_destinations = service.blocked_social_destinations
    @publication_form ||= Publications::CreateForm.new
  end

  def load_review
    service = Publications::ShowService.new(
      video_project_id: params[:video_project_id],
      publication_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @publication = service.publication
    @latest_preflight_report = service.latest_preflight_report
    @preflight_ready = service.preflight_ready
    @workflow_run = service.workflow_run
    @outbound_attempt = service.outbound_attempt
  end

  def publication_params
    params.require(:publication).permit(
      :caption,
      :render_version_id,
      :preflight_report_id,
      :decision,
      :evidence,
      :provider_reference,
      :risk_confirmed,
      destination_ids: [],
      destination_captions: {}
    )
  end
end
