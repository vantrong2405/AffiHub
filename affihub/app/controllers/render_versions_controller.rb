# frozen_string_literal: true

# Streams completed local MP4 render versions to the browser.
class RenderVersionsController < MainController
  # Sends a ready render as an MP4 download without contacting a social platform.
  def export
    service = RenderVersionExportService.new(render_version_id: params[:id]).call

    send_data(
      service.data,
      filename: service.filename,
      type: "video/mp4",
      disposition: "attachment"
    )
  end
end
