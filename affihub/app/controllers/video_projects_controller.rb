# frozen_string_literal: true

# Handles local video project import and preview screens.
class VideoProjectsController < MainController
  # Renders the local MP4 upload screen.
  def index
  end

  # Imports a local MP4 and redirects to its preview when valid.
  def create
    service = VideoImportService.new(file: params[:file])
    service.call

    render_service(
      service,
      success: -> { video_project_path(service.video_project) },
      notice: "Video đã sẵn sàng xem trước.",
      failure: :index
    )
  end

  # Loads the project, source and local render for preview.
  def show
    service = VideoPreviewService.new(video_project_id: params[:id]).call
    @video_project = service.video_project
    @source_asset = service.source_asset
    @render_version = service.render_version
  end
end
