class GoogleConnections::CallbackService < ApplicationService
  attr_reader :google_connection

  # Initializes Google OAuth callback verification using the caller's browser session.
  #
  # @param params [Hash, ActionController::Parameters] the callback query parameters
  # @param session [ActionDispatch::Request::Session, Hash] the browser session
  # @param callback_url [String] the actual callback URL received by Rails
  # @return [GoogleConnections::CallbackService] the configured service
  def initialize(params:, session:, callback_url:)
    @params = params.to_unsafe_h.deep_stringify_keys if params.respond_to?(:to_unsafe_h)
    @params ||= params.to_h.deep_stringify_keys
    @session = session
    @callback_url = callback_url
    super()
  end

  # Consumes a valid one-time state before exchanging the Google authorization code.
  #
  # @return [Boolean] whether the Google connection was stored
  def call
    return false unless step_load_configuration
    return false unless step_consume_oauth_attempt
    return false unless step_exchange_code
    return false unless step_load_profile

    step_persist_connection
    success?
  end

  private

  def step_load_configuration
    @configuration = Rails.application.config_for(:google).deep_symbolize_keys
    @oauth_configuration = @configuration.fetch(:oauth)
    true
  end

  def step_consume_oauth_attempt
    allowed_redirect_uris = @oauth_configuration.fetch(:allowed_redirect_uris)
    expected_redirect_uri = @oauth_configuration.fetch(:redirect_uri)
    unless allowed_redirect_uris.include?(@callback_url) && expected_redirect_uri == @callback_url
      return step_fail!("Địa chỉ callback Google không hợp lệ.")
    end

    state = @params["state"].to_s
    return step_fail!("Callback không có Google OAuth state hợp lệ.") if state.blank?

    attempts = @session["google_oauth_attempts"] || {}
    state_digest = Digest::SHA256.hexdigest(state)
    @oauth_attempt = attempts[state_digest]
    return step_fail!("Google OAuth state đã hết hạn, đã dùng hoặc thuộc phiên khác.") unless step_oauth_attempt_valid?

    attempts.delete(state_digest)
    @session["google_oauth_attempts"] = attempts
    return step_fail!("Người dùng đã hủy kết nối Google.") if @params["error"].present?
    return step_fail!("Google không trả authorization code.") if @params["code"].blank?

    true
  end

  def step_oauth_attempt_valid?
    return false unless @oauth_attempt
    return false unless @oauth_configuration.fetch(:allowed_redirect_uris).include?(@oauth_attempt.fetch("redirect_uri"))
    return false unless @oauth_configuration.fetch(:integrations).key?(@oauth_attempt.fetch("integration").to_sym)
    return false unless @oauth_attempt.fetch("redirect_uri") == @callback_url

    Time.iso8601(@oauth_attempt.fetch("expires_at")) > Time.current
  rescue KeyError, ArgumentError
    false
  end

  def step_exchange_code
    @token_payload = google_client.exchange_code(
      code: @params.fetch("code"),
      redirect_uri: @oauth_attempt.fetch("redirect_uri"),
      code_verifier: @oauth_attempt.fetch("code_verifier")
    )
    return true if @token_payload["access_token"].present?

    step_fail!("Google chưa trả access token cho kết nối này.")
  rescue Google::Client::ApiError
    step_fail!("Google chưa thể xác nhận kết nối. Hãy thử bắt đầu lại.")
  end

  def step_load_profile
    @profile = google_client.profile(access_token: @token_payload.fetch("access_token"))
    return true if @profile.fetch("sub", nil).present? && @profile.fetch("email", nil).present?

    step_fail!("Google không trả thông tin tài khoản hợp lệ.")
  rescue Google::Client::ApiError
    step_fail!("Không thể đọc tài khoản Google sau khi xác thực.")
  end

  def step_persist_connection
    GoogleConnection.transaction do
      @google_connection = GoogleConnection.find_or_initialize_by(
        integration: @oauth_attempt.fetch("integration"),
        google_account_id: @profile.fetch("sub")
      )
      @google_connection.assign_attributes(
        email: @profile.fetch("email"),
        access_token: @token_payload.fetch("access_token"),
        refresh_token: @token_payload["refresh_token"].presence || @google_connection.refresh_token,
        access_token_expires_at: token_expiry,
        scopes: token_scopes,
        status: :connected,
        safe_error_code: nil
      )
      @google_connection.save!
    end
    step_succeed!
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu kết nối Google.")
  end

  def google_client
    @google_client ||= Google::Client.new
  end

  def token_expiry
    expires_in = @token_payload.fetch("expires_in", 0).to_i
    expires_in.positive? ? Time.current + expires_in.seconds : nil
  end

  def token_scopes
    token_scopes = @token_payload.fetch("scope", "").split(/[\s,]+/).reject(&:blank?).uniq
    token_scopes.presence || @oauth_configuration.fetch(:integrations).fetch(@oauth_attempt.fetch("integration").to_sym).fetch(:scopes)
  end
end
