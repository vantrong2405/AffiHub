class SheetSyncs::EnqueueForScheduleService < ApplicationService
  # Initializes the Sheets side job for one explicitly saved Schedule.
  #
  # @param schedule_id [Integer] the Schedule just confirmed by the user
  # @return [SheetSyncs::EnqueueForScheduleService] the configured service
  def initialize(schedule_id:)
    @schedule_id = schedule_id
    super()
  end

  # Queues the selected render and destinations without waiting for publishing.
  #
  # @return [Boolean] whether the optional Sheets side job was accepted
  def call
    return false unless step_load_schedule

    step_enqueue_selected_destinations
    step_succeed!
    success?
  rescue ActiveJob::EnqueueError
    step_fail!("Không thể xếp Google Sheets; lịch đã lưu trong Rails.")
  end

  private

  def step_load_schedule
    @schedule = Schedule.includes(:schedule_destinations).find_by(id: @schedule_id)
    return true if @schedule

    step_fail!("Không tìm thấy lịch đã lưu để đồng bộ Google Sheets.")
  end

  def step_enqueue_selected_destinations
    connections = GoogleConnection.where(integration: "sheets", status: :connected)
      .where.not(spreadsheet_id: [ nil, "" ], worksheet_title: [ nil, "" ])

    connections.each do |connection|
      @schedule.schedule_destinations.each do |schedule_destination|
        SheetSyncs::CreateService.new(
          google_connection_id: connection.id,
          render_version_id: @schedule.render_version_id,
          social_destination_id: schedule_destination.social_destination_id
        ).call
      end
    end
  end
end
