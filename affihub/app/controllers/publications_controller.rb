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
      caption: publication_params[:caption],
      consent_attributes: publication_params[:consent_attributes] || {}
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
    @youtube_privacy_statuses = service.youtube_privacy_statuses
    @tiktok_privacy_levels = service.tiktok_privacy_levels
    @tiktok_disabled_interactions = service.tiktok_disabled_interactions
    @tiktok_creator_info_available = service.tiktok_creator_info_available
    @tiktok_cap_status = service.tiktok_cap_status
    @tiktok_cap_status_values = service.tiktok_cap_status_values
    @tiktok_brand_content_enabled = service.tiktok_brand_content_enabled
    @publication_consent_presenter = Publications::ConsentPresenter.new(
      publication: @publication,
      youtube_privacy_statuses: @youtube_privacy_statuses,
      tiktok_privacy_levels: @tiktok_privacy_levels,
      tiktok_disabled_interactions: @tiktok_disabled_interactions,
      tiktok_creator_info_available: @tiktok_creator_info_available,
      tiktok_cap_status: @tiktok_cap_status,
      tiktok_cap_status_values: @tiktok_cap_status_values,
      tiktok_brand_content_enabled: @tiktok_brand_content_enabled
    )
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
      consent_attributes: [
        :upload_terms_confirmed,
        :privacy_status,
        :self_declared_made_for_kids,
        :contains_synthetic_media,
        :privacy_level,
        :allow_comment,
        :allow_duet,
        :allow_stitch,
        :brand_organic_toggle,
        :brand_content_toggle,
        :is_aigc,
        :creator_account_private,
        :music_usage_confirmed
      ],
      destination_ids: [],
      destination_captions: {}
    )
  end
end
