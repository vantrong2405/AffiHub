# frozen_string_literal: true

# Loads a video project with its latest local source and render for preview.
class VideoPreviewService
  attr_reader :video_project, :source_asset, :render_version

  # Selects the project to preview.
  #
  # @param video_project_id [Integer, String] project identifier from the route
  # @return [VideoPreviewService]
  def initialize(video_project_id:)
    @video_project_id = video_project_id
  end

  # Loads the project and its latest source and render records.
  #
  # @return [VideoPreviewService] this service with the preview records
  def call
    @video_project = VideoProject.find(@video_project_id)
    @source_asset = video_project.source_assets.order(:id).last
    @render_version = source_asset.render_versions.order(:version_number).last
    self
  end
end
