# frozen_string_literal: true

# Loads a ready render and its bytes for local MP4 download.
class RenderVersionExportService
  attr_reader :data, :filename

  # Selects the render version to export.
  #
  # @param render_version_id [Integer, String] render version identifier from the route
  # @return [RenderVersionExportService]
  def initialize(render_version_id:)
    @render_version_id = render_version_id
  end

  # Loads the ready render's file bytes and original filename.
  #
  # @return [RenderVersionExportService] this service with the MP4 download data
  def call
    render_version = RenderVersion.ready.find(@render_version_id)
    @data = render_version.file.download
    @filename = render_version.file.filename.to_s
    self
  end
end
