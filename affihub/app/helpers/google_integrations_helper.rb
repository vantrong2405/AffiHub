module GoogleIntegrationsHelper
  # Returns the customer-facing name for a supported Google integration.
  #
  # @param integration [String, Symbol] the configured integration key
  # @return [String] the integration name
  def google_integration_name(integration)
    case integration.to_s
    when "drive" then "Google Drive"
    when "sheets" then "Google Sheets"
    else "Google"
    end
  end

  # Returns the short purpose statement for a Google integration card.
  #
  # @param integration [String, Symbol] the integration shown to the user
  # @return [String] the customer-facing description
  def google_integration_description(integration)
    case integration.to_s
    when "drive" then "Lưu bản render theo project vào Drive."
    when "sheets" then "Giữ một hàng trạng thái mới nhất cho từng render và destination."
    else "Đồng bộ tùy chọn với tài khoản Google của bạn."
    end
  end

  # Returns a readable value or the standard empty label.
  #
  # @param value [Object, nil] the optional value to display
  # @return [String] the readable value or an empty label
  def google_display_value(value)
    value.presence || "Chưa có"
  end

  # Returns the browser title for the Google connection index.
  #
  # @return [String] the page title
  def google_connections_page_title
    "Kết nối Google | AffiHub"
  end

  # Returns the browser title for a Google integration setup page.
  #
  # @param integration [String, Symbol] the selected integration
  # @return [String] the page title
  def google_connection_setup_page_title(integration)
    "Thiết lập #{google_integration_name(integration)} | AffiHub"
  end

  # Returns the browser title for one saved Google account.
  #
  # @param google_connection [GoogleConnection] the saved account
  # @return [String] the page title
  def google_connection_page_title(google_connection)
    "#{google_integration_name(google_connection.integration)} | AffiHub"
  end

  # Returns the browser title for a project's Drive export list.
  #
  # @param video_project [VideoProject] the selected project
  # @return [String] the page title
  def drive_exports_page_title(video_project)
    "Google Drive · #{video_project.name} | AffiHub"
  end

  # Returns the browser title for one Drive export.
  #
  # @param drive_export [DriveExport] the selected export
  # @return [String] the page title
  def drive_export_page_title(drive_export)
    "Drive · Bản render v#{drive_export.render_version.version_number} | AffiHub"
  end

  # Returns the browser title for a project's Sheets sync list.
  #
  # @param video_project [VideoProject] the selected project
  # @return [String] the page title
  def sheet_syncs_page_title(video_project)
    "Google Sheets · #{video_project.name} | AffiHub"
  end

  # Returns the browser title for one Sheets sync row.
  #
  # @param sheet_sync [SheetSync] the selected row
  # @return [String] the page title
  def sheet_sync_page_title(sheet_sync)
    "Sheets · v#{sheet_sync.render_version.version_number} | AffiHub"
  end

  # Returns the configured Google connection status label.
  #
  # @param status [String, Symbol] the saved account status
  # @return [String] the Vietnamese status label
  def google_connection_status_label(status)
    case status.to_s
    when "connected" then "Đã kết nối"
    when "reauth_required" then "Cần kết nối lại"
    when "revoked" then "Đã thu hồi"
    when "failed" then "Kết nối lỗi"
    else "Chưa rõ trạng thái"
    end
  end

  # Returns a daisyUI badge class for a Google account status.
  #
  # @param status [String, Symbol] the saved account status
  # @return [String] the badge classes
  def google_connection_badge_class(status)
    case status.to_s
    when "connected" then "badge-success"
    when "reauth_required", "failed" then "badge-warning"
    when "revoked" then "badge-error"
    else "badge-ghost"
    end
  end

  # Returns the Drive export status label used in lists and detail pages.
  #
  # @param status [String, Symbol] the persisted upload state
  # @return [String] the Vietnamese status label
  def drive_export_status_label(status)
    {
      "queued" => "Đang chờ",
      "retrying" => "Đang thử lại",
      "uploading" => "Đang tải lên",
      "succeeded" => "Đã lưu lên Drive",
      "waiting_for_quota" => "Chờ quota miễn phí",
      "storage_quota_exceeded" => "Drive đã đầy",
      "outcome_unknown" => "Chưa rõ kết quả",
      "manual_outcome_confirmed" => "Đã đối soát",
      "manual_outcome_not_occurred" => "Đã xác nhận chưa tải",
      "failed" => "Lỗi tải lên"
    }.fetch(status.to_s, "Chưa rõ trạng thái")
  end

  # Returns a daisyUI badge class for a Drive export state.
  #
  # @param status [String, Symbol] the persisted upload state
  # @return [String] the badge classes
  def drive_export_badge_class(status)
    case status.to_s
    when "succeeded", "manual_outcome_confirmed" then "badge-success"
    when "queued", "retrying", "uploading" then "badge-info"
    when "waiting_for_quota", "storage_quota_exceeded", "outcome_unknown" then "badge-warning"
    when "failed", "manual_outcome_not_occurred" then "badge-error"
    else "badge-ghost"
    end
  end

  # Returns the Sheets synchronization status label used in lists and details.
  #
  # @param status [String, Symbol] the persisted row state
  # @return [String] the Vietnamese status label
  def sheet_sync_status_label(status)
    {
      "queued" => "Đang chờ",
      "syncing" => "Đang đồng bộ",
      "succeeded" => "Đã cập nhật Sheets",
      "retrying" => "Đang thử lại",
      "waiting_for_quota" => "Chờ quota miễn phí",
      "outcome_unknown" => "Chưa rõ kết quả",
      "failed" => "Lỗi đồng bộ"
    }.fetch(status.to_s, "Chưa rõ trạng thái")
  end

  # Returns a daisyUI badge class for a Sheets synchronization state.
  #
  # @param status [String, Symbol] the persisted row state
  # @return [String] the badge classes
  def sheet_sync_badge_class(status)
    case status.to_s
    when "succeeded" then "badge-success"
    when "queued", "syncing", "retrying" then "badge-info"
    when "waiting_for_quota", "outcome_unknown" then "badge-warning"
    when "failed" then "badge-error"
    else "badge-ghost"
    end
  end

  # Returns a safe Vietnamese explanation for a configured machine error code.
  #
  # @param error_code [String, nil] the stored safe machine code
  # @return [String, nil] the customer-facing error explanation
  def google_safe_error_message(error_code)
    case error_code.to_s
    when "google_drive_daily_quota_exhausted", "google_sheets_daily_quota_exhausted"
      "Quota Google miễn phí đã hết. AffiHub dừng nhánh đồng bộ; hãy thử lại khi quota được làm mới."
    when "google_drive_storage_quota_exceeded"
      "Dung lượng Drive đã đầy. Bản render local vẫn được giữ; giải phóng dung lượng rồi thử lại."
    when "google_drive_upload_outcome_unknown", "google_sheets_sync_outcome_unknown"
      "Google có thể đã nhận thay đổi nhưng chưa trả xác nhận. Hãy đối soát trước khi thử lại."
    when "google_drive_rate_limit", "google_sheets_rate_limit"
      "Google đang giới hạn tạm thời. AffiHub sẽ thử lại trong giới hạn đã cấu hình."
    when "google_drive_reconnect_required", "google_sheets_reconnect_required", "google_reauth_required"
      "Kết nối Google hết hạn. Hãy kết nối lại để tiếp tục đồng bộ."
    else
      "Google chưa thể hoàn tất đồng bộ. Kiểm tra kết nối và thử lại sau."
    end
  end

  # Returns accessible Drive folders as select options, including the Drive root.
  #
  # @param drive_folders [Array<Hash>] the folders visible to this application
  # @param selected_folder_id [String, nil] the saved parent folder ID
  # @return [String] the escaped select options
  def google_drive_folder_options(drive_folders, selected_folder_id)
    options = [ [ "Thư mục gốc của Drive", "" ] ]
    drive_folders.each { |folder| options << [ folder.fetch("name", "Thư mục không tên"), folder.fetch("id") ] }
    options_for_select(options, selected_folder_id)
  end

  # Returns worksheets as select options.
  #
  # @param worksheets [Array<Hash>] the spreadsheet worksheet metadata
  # @param selected_title [String, nil] the saved or requested worksheet title
  # @return [String] the escaped select options
  def google_worksheet_options(worksheets, selected_title)
    options = worksheets.map { |worksheet| [ worksheet.fetch("title"), worksheet.fetch("title") ] }
    options_for_select(options, selected_title)
  end

  # Returns connected Google accounts as select options.
  #
  # @param google_connections [Array<GoogleConnection>] the available accounts
  # @param selected_id [Integer, String, nil] the currently selected account
  # @return [String] the escaped select options
  def google_connection_options(google_connections, selected_id)
    options = google_connections.map do |google_connection|
      [ "#{google_integration_name(google_connection.integration)} · #{google_connection.email}", google_connection.id ]
    end
    options_for_select(options, selected_id)
  end

  # Returns render versions as readable select options.
  #
  # @param render_versions [Array<RenderVersion>] the eligible render versions
  # @param selected_id [Integer, String, nil] the selected render version
  # @return [String] the escaped select options
  def google_render_version_options(render_versions, selected_id = nil)
    options = render_versions.map do |render_version|
      [ render_version_option_label(render_version), render_version.id ]
    end
    options_for_select(options, selected_id)
  end

  # Returns a readable project render label for a select or checkbox.
  #
  # @param render_version [RenderVersion] the immutable render version
  # @return [String] the Vietnamese render label
  def render_version_option_label(render_version)
    "Bản render v#{render_version.version_number} · #{google_local_time(render_version.created_at)}"
  end

  # Formats a timestamp using the application's short local date format.
  #
  # @param value [Time, ActiveSupport::TimeWithZone, nil] the stored time
  # @return [String] the formatted local time or a safe empty label
  def google_local_time(value)
    value.present? ? l(value, format: :short) : "Chưa có"
  end
end
