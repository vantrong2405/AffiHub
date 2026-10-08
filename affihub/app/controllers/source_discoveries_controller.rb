class SourceDiscoveriesController < MainController
  # Loads the YouTube search form for the selected project.
  #
  # @return [ActionController::Metal::Response] the search form response
  def new
    service = SourceDiscoveries::NewService.new(video_project_id: params[:video_project_id])
    service.call
    step_assign_form(service)
  end

  # Searches YouTube and redirects to the persisted project-scoped results.
  #
  # @return [ActionController::Metal::Response] the search response
  def create
    service = SourceDiscoveries::CreateService.new(
      video_project_id: params[:video_project_id],
      search_type: source_discovery_params[:search_type],
      search_query: source_discovery_params[:search_query],
      region_code: source_discovery_params[:region_code],
      video_category_id: source_discovery_params[:video_category_id]
    )
    service.call
    step_assign_form(service)

    render_service(service, failure: :new, notice: "Đã tìm xong video trên YouTube.") do
      video_project_source_discovery_path(service.video_project, service.source_discovery)
    end
  end

  # Loads the persisted result set belonging to the selected project.
  #
  # @return [ActionController::Metal::Response] the result page response
  def show
    service = SourceDiscoveries::ShowService.new(
      video_project_id: params[:video_project_id],
      source_discovery_id: params[:id]
    )
    service.call
    @video_project = service.video_project
    @source_discovery = service.source_discovery
    @search_results = service.source_discovery.source_discovery_results
    @regions = service.regions
    @video_categories = service.video_categories
  end

  private

  def step_assign_form(service)
    @video_project = service.video_project
    @source_discovery = service.source_discovery
    @regions = service.regions
    @video_categories = service.video_categories
    @default_region_code = service.default_region_code
  end

  def source_discovery_params
    params.require(:source_discovery).permit(:search_type, :search_query, :region_code, :video_category_id)
  end
end
