class SheetSyncs::EnqueueForRenderService < ApplicationService
  # Initializes Sheets refresh after one Drive render upload completes.
  #
  # @param render_version_id [Integer] the render whose Drive link changed
  # @return [SheetSyncs::EnqueueForRenderService] the configured service
  def initialize(render_version_id:)
    @render_version_id = render_version_id
    super()
  end

  # Requeues only existing Publication destinations for the completed render.
  #
  # @return [Boolean] whether the optional side-job request was accepted
  def call
    return false unless step_load_render_version

    step_enqueue_existing_destinations
    step_succeed!
    success?
  rescue ActiveJob::EnqueueError
    step_fail!("Không thể xếp lại Google Sheets; kết quả Drive vẫn được giữ.")
  end

  private

  def step_load_render_version
    @render_version = RenderVersion.find_by(id: @render_version_id)
    return true if @render_version

    step_fail!("Không tìm thấy render version cần cập nhật link Drive.")
  end

  def step_enqueue_existing_destinations
    connections = GoogleConnection.where(integration: "sheets", status: :connected)
      .where.not(spreadsheet_id: [ nil, "" ], worksheet_title: [ nil, "" ])
    destination_ids = Publication.where(render_version_id: @render_version.id)
      .distinct.pluck(:social_destination_id)

    connections.each do |connection|
      destination_ids.each do |social_destination_id|
        SheetSyncs::CreateService.new(
          google_connection_id: connection.id,
          render_version_id: @render_version.id,
          social_destination_id:
        ).call
      end
    end
  end
end
