class GoogleConnections::UpdateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys

  # The Google connection whose optional integration settings were updated.
  # @return [GoogleConnection, nil]
  attr_reader :google_connection

  # Initializes a Drive folder or Sheets document/tab configuration update.
  #
  # @param google_connection_id [Integer] the persisted Google connection
  # @param attributes [Hash] the submitted integration settings
  # @return [GoogleConnections::UpdateService] the configured service
  def initialize(google_connection_id:, attributes:)
    @google_connection_id = google_connection_id
    @attributes = attributes.to_h.stringify_keys
    super()
  end

  # Validates provider access before saving the selected Drive folder or Sheet tab.
  #
  # @return [Boolean] whether the selected integration settings were saved
  def call
    return false unless step_load_connection
    return false unless step_validate_connection
    return false unless step_prepare_settings
    return false unless step_save_settings

    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu cấu hình Google.")
  rescue Google::Client::ApiError
    step_fail!("Không thể xác minh quyền truy cập Google cho lựa chọn này.")
  end

  private

  def step_load_connection
    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    return true if google_connection

    step_fail!("Không tìm thấy kết nối Google cần cấu hình.")
  end

  def step_validate_connection
    return step_fail!("Kết nối Google cần đăng nhập lại trước khi đổi cấu hình.") unless google_connection.connected?
    return true if GoogleConnection::INTEGRATIONS.include?(google_connection.integration)

    step_fail!("Loại kết nối Google không được hỗ trợ.")
  end

  def step_prepare_settings
    return step_prepare_drive_folder if google_connection.integration == "drive"
    return step_prepare_spreadsheet if google_connection.integration == "sheets"

    step_fail!("Loại kết nối Google không được hỗ trợ.")
  end

  def step_prepare_drive_folder
    @drive_parent_folder_id = @attributes.fetch("drive_parent_folder_id", "").to_s.strip
    return true if @drive_parent_folder_id.blank?

    return false unless step_load_access_token

    @drive_folder = google_client.find_drive_folder(folder_id: @drive_parent_folder_id)
    valid_folder = @drive_folder.fetch("mimeType", nil) == CONFIGURATION.dig(:drive, :folder_mime_type)
    return true if valid_folder

    step_fail!("Chọn một thư mục Google Drive có thể truy cập bằng kết nối này.")
  end

  def step_prepare_spreadsheet
    @spreadsheet_id = @attributes.fetch("spreadsheet_id", "").to_s.strip
    return step_fail!("Hãy chọn một bảng tính Google Sheets bằng Google Picker.") unless step_valid_spreadsheet_id?(@spreadsheet_id)
    return step_fail!("Nhập tên tab cần đồng bộ.") if @attributes.fetch("worksheet_title", "").to_s.strip.blank?
    return false unless step_load_access_token

    @worksheets = google_client.spreadsheet_worksheets(spreadsheet_id: @spreadsheet_id)
    selected_title = @attributes.fetch("worksheet_title").to_s.strip
    return true if @worksheets.any? { |worksheet| worksheet.fetch("title", nil) == selected_title }

    step_fail!("Tab đã chọn không có trong spreadsheet hoặc chưa được cấp quyền.")
  end

  def step_valid_spreadsheet_id?(input)
    input.match?(/\A[A-Za-z0-9_-]{10,}\z/)
  end

  def step_load_access_token
    token_service = GoogleConnections::AccessTokenService.new(google_connection_id: google_connection.id)
    return true if token_service.call && step_build_google_client(token_service.access_token)

    step_fail!(token_service.errors.full_messages.to_sentence.presence || "Kết nối Google cần đăng nhập lại.")
  end

  def step_build_google_client(access_token)
    @google_client = Google::Client.new(access_token:)
    true
  end

  def google_client
    @google_client
  end

  def step_save_settings
    if google_connection.integration == "drive"
      google_connection.update!(drive_parent_folder_id: @drive_parent_folder_id.presence)
    else
      google_connection.update!(spreadsheet_id: @spreadsheet_id, worksheet_title: @attributes.fetch("worksheet_title").to_s.strip)
    end
    true
  end
end
