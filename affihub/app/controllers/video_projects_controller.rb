class VideoProjectsController < MainController
  # Loads all local projects for the workspace index.
  #
  # @return [ActionController::Metal::Response] the project list response
  def index
    service = VideoProjects::IndexService.new
    service.call
    @video_projects = service.video_projects
  end

  # Builds the new project form.
  #
  # @return [ActionController::Metal::Response] the new project response
  def new
    service = VideoProjects::NewService.new
    service.call
    @video_project = service.video_project
  end

  # Creates a project and redirects to its workspace.
  #
  # @return [ActionController::Metal::Response] the project create response
  def create
    service = VideoProjects::CreateService.new(name: video_project_params[:name])
    service.call
    @video_project = service.video_project

    render_service(service, failure: :new, notice: "Đã tạo project.") do
      video_project_path(service.video_project)
    end
  end

  # Loads a project and its local source/render history.
  #
  # @return [ActionController::Metal::Response] the project workspace response
  def show
    service = VideoProjects::ShowService.new(video_project_id: params[:id])
    service.call
    @video_project = service.video_project
    @source_assets = service.source_assets
    @render_versions = service.render_versions
  end

  # Loads the selected project for its edit form.
  #
  # @return [ActionController::Metal::Response] the edit form response
  def edit
    service = VideoProjects::EditService.new(video_project_id: params[:id])
    service.call
    @video_project = service.video_project
  end

  # Updates a project name and returns the form when validation fails.
  #
  # @return [ActionController::Metal::Response] the project update response
  def update
    service = VideoProjects::UpdateService.new(
      video_project_id: params[:id],
      name: video_project_params[:name]
    )
    service.call
    @video_project = service.video_project

    render_service(service, failure: :edit, notice: "Đã cập nhật project.") do
      video_project_path(service.video_project)
    end
  end

  # Deletes an empty project or keeps projects that own media.
  #
  # @return [ActionController::Metal::Response] the project delete response
  def destroy
    service = VideoProjects::DestroyService.new(video_project_id: params[:id])
    service.call

    render_service(
      service,
      success: video_projects_path,
      failure_redirect: video_project_path(service.video_project),
      notice: "Đã xóa project.",
      alert: "Không thể xóa project đang chứa source hoặc render."
    )
  end

  private

  def video_project_params
    params.require(:video_project).permit(:name)
  end
end
