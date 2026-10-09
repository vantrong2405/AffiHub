class SheetSyncs::SyncService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  SHEETS_CONFIGURATION = CONFIGURATION.fetch(:sheets)

  # The SheetSync row being reconciled.
  # @return [SheetSync, nil]
  attr_reader :sheet_sync

  # Initializes one serialized Sheets upsert.
  #
  # @param sheet_sync_id [Integer] the persisted sync request
  # @return [SheetSyncs::SyncService] the configured service
  def initialize(sheet_sync_id:)
    @sheet_sync_id = sheet_sync_id
    super()
  end

  # Upserts the latest publication state into its keyed Sheet row.
  #
  # @return [Boolean] whether Google confirmed the upsert
  def call
    return false unless step_load_sync
    return false unless step_validate_sync

    sheet_sync.with_lock do
      return step_succeed_for_completed_sync if sheet_sync.succeeded?
      return false unless step_mark_syncing
      return false unless step_get_access_token

      @row_number = step_google_client.upsert_sheet_row(
        spreadsheet_id: sheet_sync.google_connection.spreadsheet_id,
        worksheet_title: sheet_sync.google_connection.worksheet_title,
        row_key: sheet_sync.sheet_row_key,
        values: step_row_values
      )
      step_mark_succeeded
    end
  rescue Google::Client::DailyQuotaExceeded
    step_mark_waiting_for_quota
  rescue Google::Client::RateLimitError => error
    step_mark_retrying
    raise error
  rescue Google::Client::NetworkError, Timeout::Error => error
    step_mark_outcome_unknown
    raise error
  rescue Google::Client::ApiError => error
    step_mark_failed(error.reason)
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_sync
    @sheet_sync = SheetSync.includes(:google_connection, :social_destination, render_version: :video_project)
      .find_by(id: @sheet_sync_id)
    return true if sheet_sync

    step_fail!("Không tìm thấy yêu cầu đồng bộ Google Sheets.")
  end

  def step_validate_sync
    return step_fail!("Kết nối đã chọn không phải Google Sheets.") unless sheet_sync.google_connection.integration == "sheets"
    return step_fail!("Kết nối Google Sheets cần đăng nhập lại.") unless sheet_sync.google_connection.connected?
    return step_fail!("Hãy chọn spreadsheet và tab trước khi đồng bộ.") if
      sheet_sync.google_connection.spreadsheet_id.blank? || sheet_sync.google_connection.worksheet_title.blank?

    true
  end

  def step_mark_syncing
    sheet_sync.update!(status: :syncing, safe_error_code: nil)
    true
  end

  def step_get_access_token
    token_service = GoogleConnections::AccessTokenService.new(
      google_connection_id: sheet_sync.google_connection_id
    )
    return step_mark_reconnect_required unless token_service.call

    @google_client = Google::Client.new(access_token: token_service.access_token)
    true
  end

  def step_google_client
    @google_client
  end

  def step_row_values
    publication = step_latest_publication
    schedule_destination = step_latest_schedule_destination unless publication
    [
      sheet_sync.sheet_row_key,
      sheet_sync.render_version.video_project.name,
      sheet_sync.render_version_id.to_s,
      sheet_sync.social_destination.provider,
      sheet_sync.social_destination.name,
      publication&.caption || schedule_destination&.caption || "",
      step_drive_url,
      publication&.status || (schedule_destination ? "scheduled" : ""),
      publication&.platform_post_id.to_s,
      publication&.permalink.to_s,
      publication&.published_at&.utc&.iso8601.to_s,
      publication&.safe_error_code.to_s,
      (publication&.updated_at || schedule_destination&.updated_at || Time.current).utc.iso8601
    ]
  end

  def step_latest_publication
    Publication.where(
      render_version_id: sheet_sync.render_version_id,
      social_destination_id: sheet_sync.social_destination_id
    ).order(created_at: :desc, id: :desc).first
  end

  def step_latest_schedule_destination
    ScheduleDestination.joins(:schedule)
      .where(
        schedules: { render_version_id: sheet_sync.render_version_id },
        social_destination_id: sheet_sync.social_destination_id
      )
      .order("schedules.created_at DESC, schedule_destinations.id DESC")
      .first
  end

  def step_drive_url
    DriveExport.where(render_version_id: sheet_sync.render_version_id, status: :succeeded)
      .where.not(drive_url: [ nil, "" ])
      .order(updated_at: :desc, id: :desc)
      .pick(:drive_url).to_s
  end

  def step_mark_succeeded
    sheet_sync.update!(
      status: :succeeded,
      row_number: @row_number,
      safe_error_code: nil,
      last_synced_at: Time.current
    )
    step_succeed!
    success?
  end

  def step_mark_waiting_for_quota
    sheet_sync.update!(
      status: :waiting_for_quota,
      safe_error_code: SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:daily_quota)
    )
    step_fail!("Google Sheets đã hết quota API tiêu chuẩn; AffiHub chờ quota khả dụng và không bật tính phí.")
  end

  def step_mark_retrying
    sheet_sync.update!(
      status: :retrying,
      safe_error_code: SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:rate_limit)
    )
  end

  def step_mark_outcome_unknown
    sheet_sync.update!(
      status: :outcome_unknown,
      safe_error_code: SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:sync_outcome_unknown)
    )
  end

  def step_mark_failed(reason)
    sheet_sync.update!(
      status: :failed,
      safe_error_code: reason.presence || SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:api_error)
    )
    step_fail!("Google Sheets chưa thể cập nhật hàng hiện trạng.")
  end

  def step_mark_reconnect_required
    sheet_sync.update!(
      status: :failed,
      safe_error_code: SHEETS_CONFIGURATION.fetch(:safe_error_codes).fetch(:reconnect_required)
    )
    step_fail!("Kết nối Google Sheets cần đăng nhập lại.")
  end

  def step_succeed_for_completed_sync
    step_succeed!
    success?
  end
end
