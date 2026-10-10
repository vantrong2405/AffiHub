class SourceAssetsController < MainController
  # Loads local source assets for one project.
  #
  # @return [ActionController::Metal::Response] the source list response
  def index
    service = SourceAssets::IndexService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
    @source_assets = service.source_assets
  end

  # Loads the project for a local file upload.
  #
  # @return [ActionController::Metal::Response] the upload form response
  def new
    service = SourceAssets::NewService.new(video_project_id: params[:video_project_id])
    service.call
    @video_project = service.video_project
  end

  # Persists a local upload and queues source inspection.
  #
  # @return [ActionController::Metal::Response] the source create response
  def create
    project_service = SourceAssets::NewService.new(video_project_id: params[:video_project_id])
    project_service.call
    service = step_create_service(project_service.video_project)
    service.call
    @video_project = service.video_project

    render_service(service, failure: :new, notice: step_success_notice(service)) do
      video_project_source_asset_path(service.video_project, service.source_asset)
    end
  end

  # Loads one source asset from the selected project.
  #
  # @return [ActionController::Metal::Response] the source detail response
  def show
    service = SourceAssets::ShowService.new(
      video_project_id: params[:video_project_id],
      source_asset_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @source_asset = service.source_asset
  end

  private

  def step_create_service(video_project)
    return SourceAssets::CreateService.new(video_project:, file: source_asset_params[:file]) if source_asset_params[:file].present?

    if source_asset_params[:youtube_discovery_metadata_id].present?
      return SourceAssets::CreateFromYoutubeResultService.new(
        video_project:,
        source_discovery_id: source_asset_params[:source_discovery_id],
        discovery_metadata_id: source_asset_params[:youtube_discovery_metadata_id],
        rights_confirmed: source_asset_params[:rights_confirmed]
      )
    end

    SourceAssets::CreateFromUrlService.new(
      video_project:,
      url: source_asset_params[:url],
      rights_confirmed: source_asset_params[:rights_confirmed]
    )
  end

  def source_asset_params
    params.require(:source_asset).permit(
      :file,
      :url,
      :rights_confirmed,
      :source_discovery_id,
      :youtube_discovery_metadata_id
    )
  end

  def step_success_notice(service)
    return "Đã nhận yêu cầu tải video. Worker sẽ xử lý trong nền." if service.source_asset&.source_type == "url_download"

    "Đã nhận file. Đang kiểm tra video."
  end
end
