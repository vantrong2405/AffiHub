class GoogleConnections::AccessTokenService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys

  attr_reader :access_token

  # Initializes retrieval or refresh of one persisted Google connection token.
  #
  # @param google_connection_id [Integer] the authorized Google connection
  # @return [GoogleConnections::AccessTokenService] the configured service
  def initialize(google_connection_id:)
    @google_connection_id = google_connection_id
    super()
  end

  # Returns a usable access token, refreshing it when it is near expiry.
  #
  # @return [Boolean] whether a usable access token is available
  def call
    return false unless step_load_connection
    return false unless step_validate_connection
    return step_use_current_token if step_current_token_is_valid?

    step_refresh_token
    success?
  end

  private

  def step_load_connection
    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    return true if @google_connection

    step_fail!("Không tìm thấy kết nối Google.")
  end

  def step_validate_connection
    return true if @google_connection.connected?

    step_fail!("Kết nối Google cần đăng nhập lại trước khi đồng bộ.")
  end

  def step_current_token_is_valid?
    refresh_at = Time.current + CONFIGURATION.fetch(:token_refresh_skew_seconds).seconds
    @google_connection.access_token_expires_at.present? && @google_connection.access_token_expires_at > refresh_at
  end

  def step_use_current_token
    @access_token = @google_connection.access_token
    step_succeed!
    success?
  end

  def step_refresh_token
    return step_mark_reauthentication_required if @google_connection.refresh_token.blank?

    response = Google::Client.new.refresh_access_token(refresh_token: @google_connection.refresh_token)
    return step_fail!("Google chưa trả access token mới.") if response.fetch("access_token", nil).blank?

    expires_in = response.fetch("expires_in", 0).to_i
    @google_connection.update!(
      access_token: response.fetch("access_token"),
      refresh_token: response["refresh_token"].presence || @google_connection.refresh_token,
      access_token_expires_at: expires_in.positive? ? Time.current + expires_in.seconds : nil,
      status: :connected,
      safe_error_code: nil
    )
    @access_token = @google_connection.access_token
    step_succeed!
  rescue Google::Client::InvalidGrantError
    step_mark_reauthentication_required
  rescue Google::Client::ApiError
    step_fail!("Google chưa thể làm mới quyền truy cập. Hãy thử lại sau.")
  end

  def step_mark_reauthentication_required
    reconnect_code = CONFIGURATION.dig(:oauth_errors, :reconnect_required)
    @google_connection.update!(status: :reauth_required, safe_error_code: reconnect_code)
    step_fail!("Kết nối Google hết hạn. Hãy kết nối lại để tiếp tục đồng bộ.")
  end
end
