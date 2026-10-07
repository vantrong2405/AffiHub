class ConnectionCallbacks::ShowService < ApplicationService
  attr_reader :social_connection

  # Initializes validation and completion of a provider callback.
  #
  # @param provider [String] the provider in the callback route
  # @param params [Hash, ActionController::Parameters] the callback parameters
  # @param session [ActionDispatch::Request::Session, Hash] the browser session
  # @param callback_url [String] the actual callback URL received by Rails
  # @return [ConnectionCallbacks::ShowService] the configured service
  def initialize(provider:, params:, session:, callback_url:)
    @provider = provider.to_s
    @params = params.to_unsafe_h.deep_stringify_keys if params.respond_to?(:to_unsafe_h)
    @params ||= params.to_h.deep_stringify_keys
    @session = session
    @callback_url = callback_url
    super()
  end

  # Consumes the session-bound state before exchanging the authorization code.
  #
  # @return [Boolean] whether the connection was stored
  def call
    return false unless step_load_provider_configuration
    return false unless step_consume_oauth_attempt
    return false unless step_exchange_code
    return false unless step_load_profile

    step_persist_connection
    success?
  end

  private

  def step_load_provider_configuration
    meta_configuration = Rails.application.config_for(:meta).deep_symbolize_keys
    @provider_configuration = meta_configuration.fetch(:providers).fetch(@provider.to_sym)
    true
  rescue KeyError
    step_fail!("Callback của nền tảng không được hỗ trợ.")
  end

  def step_consume_oauth_attempt
    allowed_uris = @provider_configuration.fetch(:allowed_redirect_uris)
    expected_uri = @provider_configuration.fetch(:redirect_uri)
    unless allowed_uris.include?(@callback_url) && expected_uri == @callback_url
      return step_fail!("Địa chỉ callback OAuth không hợp lệ.")
    end

    state = @params["state"].to_s
    return step_fail!("Callback không có OAuth state hợp lệ.") if state.blank?

    attempts = @session["social_oauth_attempts"] || {}
    digest = Digest::SHA256.hexdigest(state)
    @oauth_attempt = attempts[digest]
    return step_fail!("OAuth state đã hết hạn, đã dùng hoặc thuộc phiên khác.") unless step_oauth_attempt_valid?

    attempts.delete(digest)
    @session["social_oauth_attempts"] = attempts
    return step_fail!("Người dùng đã hủy kết nối.") if @params["error"].present?
    return step_fail!("Callback không trả authorization code.") if @params["code"].blank?

    true
  end

  def step_oauth_attempt_valid?
    return false unless @oauth_attempt
    return false unless @oauth_attempt.fetch("provider") == @provider
    return false unless @oauth_attempt.fetch("redirect_uri") == @callback_url

    Time.iso8601(@oauth_attempt.fetch("expires_at")) > Time.current
  rescue KeyError, ArgumentError
    false
  end

  def step_exchange_code
    @token_payload = Meta::Client.new.exchange_code(
      code: @params.fetch("code"),
      redirect_uri: @oauth_attempt.fetch("redirect_uri"),
      code_verifier: @oauth_attempt["code_verifier"]
    )
    return true if @token_payload["access_token"].present?

    step_fail!("Meta không trả access token cho kết nối này.")
  rescue Meta::Client::Error
    step_fail!("Meta chưa thể xác nhận kết nối. Hãy thử bắt đầu lại.")
  end

  def step_load_profile
    @profile = Meta::Client.new.profile(access_token: @token_payload.fetch("access_token"))
    return true if @profile["id"].present? && @profile["name"].present?

    step_fail!("Meta không trả thông tin profile hợp lệ.")
  rescue Meta::Client::Error
    step_fail!("Không thể đọc profile Meta sau khi xác thực.")
  end

  def step_persist_connection
    @social_connection = SocialConnection.find_or_initialize_by(
      provider: @provider,
      external_user_id: @profile.fetch("id")
    )
    @social_connection.assign_attributes(
      name: @profile.fetch("name"),
      access_token: @token_payload.fetch("access_token"),
      token_expires_at: token_expiry,
      status: :connected
    )
    @social_connection.save!
    step_succeed!
  end

  def token_expiry
    expires_in = @token_payload["expires_in"].to_i
    expires_in.positive? ? Time.current + expires_in.seconds : nil
  end
end
