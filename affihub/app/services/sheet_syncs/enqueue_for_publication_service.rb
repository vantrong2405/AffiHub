class SheetSyncs::EnqueueForPublicationService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  SHEETS_CONFIGURATION = CONFIGURATION.fetch(:sheets)

  # Initializes a side-job request for one persisted Publication.
  #
  # @param publication_id [Integer] the publication whose current state should sync
  # @return [SheetSyncs::EnqueueForPublicationService] the configured service
  def initialize(publication_id:)
    @publication_id = publication_id
    super()
  end

  # Queues one Sheets row for each configured Sheets connection.
  #
  # @return [Boolean] whether the optional side-job request was accepted
  def call
    return false unless step_load_publication
    unless step_syncable_status?
      step_succeed!
      return success?
    end

    step_enqueue_connected_rows
    step_succeed!
    success?
  rescue ActiveJob::EnqueueError
    step_fail!("Không thể đưa Google Sheets vào hàng đợi; Publication vẫn được giữ trong Rails.")
  end

  private

  def step_load_publication
    @publication = Publication.find_by(id: @publication_id)
    return true if @publication

    step_fail!("Không tìm thấy Publication cần đồng bộ.")
  end

  def step_syncable_status?
    SHEETS_CONFIGURATION.fetch(:publication_trigger_statuses).include?(@publication.status)
  end

  def step_enqueue_connected_rows
    connections = GoogleConnection.where(integration: "sheets", status: :connected)
      .where.not(spreadsheet_id: [ nil, "" ], worksheet_title: [ nil, "" ])
    connections.each do |connection|
      service = SheetSyncs::CreateService.new(
        google_connection_id: connection.id,
        render_version_id: @publication.render_version_id,
        social_destination_id: @publication.social_destination_id
      )
      service.call
    end
  end
end
