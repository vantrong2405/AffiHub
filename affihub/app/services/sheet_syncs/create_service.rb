class SheetSyncs::CreateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  SHEETS_CONFIGURATION = CONFIGURATION.fetch(:sheets)

  # The idempotent SheetSync row requested for this destination.
  # @return [SheetSync, nil]
  attr_reader :sheet_sync

  # Initializes an explicit Sheets sync request for one render and destination.
  #
  # @param google_connection_id [Integer] the configured Sheets connection
  # @param render_version_id [Integer] the render version selected for sync
  # @param social_destination_id [Integer] the publication destination
  # @return [SheetSyncs::CreateService] the configured service
  def initialize(google_connection_id:, render_version_id:, social_destination_id:)
    @google_connection_id = google_connection_id
    @render_version_id = render_version_id
    @social_destination_id = social_destination_id
    super()
  end

  # Creates or safely requeues the current row for one render and destination.
  #
  # @return [Boolean] whether one SheetSync was accepted
  def call
    @enqueue_sync = false
    return false unless step_load_resources
    return false unless step_validate_request
    return false unless step_create_or_requeue_sync

    step_enqueue_sync if @enqueue_sync
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    step_fail!("Không thể lưu yêu cầu đồng bộ Google Sheets.")
  end

  private

  def step_load_resources
    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    @render_version = RenderVersion.includes(:video_project).find_by(id: @render_version_id)
    @social_destination = SocialDestination.find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy kết nối Google Sheets.") unless @google_connection
    return step_fail!("Không tìm thấy bản render đã chọn.") unless @render_version
    return step_fail!("Không tìm thấy destination đã chọn.") unless @social_destination

    true
  end

  def step_validate_request
    return step_fail!("Kết nối đã chọn không phải Google Sheets.") unless @google_connection.integration == "sheets"
    return step_fail!("Google Sheets cần kết nối lại trước khi đồng bộ.") unless @google_connection.connected?
    return step_fail!("Hãy chọn một spreadsheet và tab trước khi đồng bộ.") if
      @google_connection.spreadsheet_id.blank? || @google_connection.worksheet_title.blank?

    true
  end

  def step_create_or_requeue_sync
    SheetSync.transaction do
      @sheet_sync = SheetSync.lock.find_by(
        google_connection: @google_connection,
        render_version: @render_version,
        social_destination: @social_destination
      )

      if @sheet_sync
        return true if @sheet_sync.queued? || @sheet_sync.syncing?

        @sheet_sync.update!(status: :queued, safe_error_code: nil)
      else
        @sheet_sync = SheetSync.create!(
          google_connection: @google_connection,
          render_version: @render_version,
          social_destination: @social_destination,
          sheet_row_key: step_row_key,
          status: :queued
        )
      end
      @enqueue_sync = true
    end
    true
  end

  def step_row_key
    project_id = @render_version.video_project_id
    render_version_id = @render_version.id
    destination_id = @social_destination.id
    "#{SHEETS_CONFIGURATION.fetch(:row_key_prefix)}#{project_id}-render-#{render_version_id}-destination-#{destination_id}"
  end

  def step_enqueue_sync
    SheetSyncs::SyncJob.perform_later(sheet_sync.id)
  end
end
