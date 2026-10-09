class GoogleConnections::ShowService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys.freeze

  # The saved Google account being configured.
  # @return [GoogleConnection, nil]
  attr_reader :google_connection

  # The Drive folders visible under the granted file scope.
  # @return [Array<Hash>]
  attr_reader :drive_folders

  # The worksheet tabs available in the entered or saved spreadsheet.
  # @return [Array<Hash>]
  attr_reader :worksheets

  # The spreadsheet ID selected for the settings form.
  # @return [String]
  attr_reader :spreadsheet_id

  # The public Google Picker configuration rendered by the settings page.
  # @return [Hash{Symbol => String}]
  attr_reader :picker_configuration

  # Reports whether the Google Picker has the required public configuration.
  # @return [Boolean]
  attr_reader :picker_ready

  # The worksheet title currently selected in the form.
  # @return [String]
  attr_reader :worksheet_title

  # A safe message shown when Google options could not be loaded.
  # @return [String, nil]
  attr_reader :option_load_error

  # Reports whether the page has an option loading error to display.
  # @return [Boolean]
  attr_reader :has_option_load_error

  # Reports whether this account is configured for Drive.
  # @return [Boolean]
  attr_reader :drive_integration

  # Reports whether this Google account can currently be used.
  # @return [Boolean]
  attr_reader :connection_connected

  # Reports whether at least one worksheet was found in the requested spreadsheet.
  # @return [Boolean]
  attr_reader :has_worksheets

  # Initializes the selected connection settings page.
  #
  # @param google_connection_id [Integer] the saved connection
  # @param spreadsheet_id [String, nil] the spreadsheet to inspect for tabs
  # @param worksheet_title [String, nil] the tab selected by the browser
  # @return [GoogleConnections::ShowService] the configured service
  def initialize(google_connection_id:, spreadsheet_id: nil, worksheet_title: nil)
    @google_connection_id = google_connection_id
    @spreadsheet_input = spreadsheet_id.to_s.strip
    @worksheet_title_input = worksheet_title.to_s
    @drive_folders = []
    @worksheets = []
    @has_option_load_error = false
    @has_worksheets = false
    super()
  end

  # Loads the connection and only the options for its selected integration.
  #
  # @return [Boolean] whether the connection settings can be displayed
  def call
    return false unless step_load_connection

    step_prepare_form_values
    step_load_remote_options if google_connection.connected?
    step_succeed!
    success?
  end

  private

  def step_load_connection
    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    return true if google_connection

    step_fail!("Không tìm thấy kết nối Google.")
  end

  def step_prepare_form_values
    @drive_integration = google_connection.integration == "drive"
    @connection_connected = google_connection.connected?
    @spreadsheet_id = @spreadsheet_input.presence || google_connection.spreadsheet_id.to_s
    @worksheet_title = @worksheet_title_input.presence || google_connection.worksheet_title.to_s
    @picker_configuration = {
      app_id: CONFIGURATION.dig(:picker, :app_id).to_s,
      client_id: CONFIGURATION.dig(:oauth, :client_id).to_s,
      developer_key: CONFIGURATION.dig(:picker, :developer_key).to_s,
      scope: CONFIGURATION.dig(:picker, :scope).to_s,
      spreadsheet_mime_type: CONFIGURATION.dig(:picker, :spreadsheet_mime_type).to_s
    }
    @picker_ready = picker_configuration.values.all?(&:present?)
  end

  def step_load_remote_options
    return unless step_load_access_token

    @google_client = Google::Client.new(access_token: @access_token)
    return step_load_drive_folders if drive_integration

    step_load_worksheets
  rescue Google::Client::ApiError
    @option_load_error = "Google chưa thể tải các lựa chọn. Hãy thử lại sau."
    @has_option_load_error = true
  end

  def step_load_drive_folders
    @drive_folders = google_client.list_drive_folders.sort_by { |folder| folder.fetch("name", "").downcase }
  end

  def step_load_worksheets
    @has_worksheets = false
    return if spreadsheet_id.blank?

    unless step_valid_spreadsheet_id?(spreadsheet_id)
      @option_load_error = "Mã bảng tính không hợp lệ. Hãy chọn lại bằng Google Picker."
      @has_option_load_error = true
      return
    end

    @worksheets = google_client.spreadsheet_worksheets(spreadsheet_id: spreadsheet_id)
    @has_worksheets = worksheets.any?
  rescue Google::Client::ApiError
    @option_load_error = "Không đọc được bảng tính. Hãy kiểm tra quyền truy cập hoặc chọn lại bằng Google Picker."
    @has_option_load_error = true
    @has_worksheets = false
  end

  def step_load_access_token
    token_service = GoogleConnections::AccessTokenService.new(google_connection_id: google_connection.id)
    return true if token_service.call && step_store_access_token(token_service.access_token)

    @option_load_error = "Kết nối Google cần đăng nhập lại trước khi tải lựa chọn."
    @has_option_load_error = true
    false
  end

  def step_store_access_token(access_token)
    @access_token = access_token
    true
  end

  def google_client
    @google_client
  end

  def step_valid_spreadsheet_id?(input)
    input.match?(/\A[A-Za-z0-9_-]{10,}\z/)
  end
end
