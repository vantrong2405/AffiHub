class DashboardController < MainController
  # Sends the local dashboard entry point to the project workspace list.
  #
  # @return [ActionController::Metal::Response] the project list redirect
  def index
    redirect_to video_projects_path
  end
end
