class AiProviderCallbacks::ShowService < ApplicationService
  attr_reader :ai_provider_connection

  # Initializes validation and completion of a provider callback.
  #
  # @param params [Hash, ActionController::Parameters] the callback parameters
  # @param session [ActionDispatch::Request::Session, Hash] the browser session
  # @param callback_url [String] the callback URI received by Rails
  # @return [AiProviderCallbacks::ShowService] the configured service
  def initialize(params:, session:, callback_url:)
    @params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h.deep_stringify_keys : params.to_h.deep_stringify_keys
    @session = session
    @callback_url = callback_url
    super()
  end

  # Consumes the session-bound state before exchanging the authorization code.
  #
  # @return [Boolean] whether the provider connection was saved
  def call
    return false unless step_load_oauth_attempt
    return false unless step_load_provider_configuration
    return false unless step_consume_oauth_attempt
    return false unless step_validate_callback_result
    return false unless step_validate_returned_client_id
    return false unless step_exchange_code
    return false unless step_verify_identity
    return false unless step_validate_nonce
    return false unless step_validate_selected_identity

    step_load_models
    return false unless success?

    step_persist_connection
    success?
  end

  private

  def step_load_oauth_attempt
    state = @params["state"].to_s
    return step_fail!("Callback không có OAuth state hợp lệ.") if state.blank?

    @state_digest = Digest::SHA256.hexdigest(state)
    attempts = @session["ai_provider_oauth_attempts"] || {}
    @oauth_attempt = attempts[@state_digest]
    return step_fail!("OAuth state đã hết hạn, đã dùng hoặc thuộc phiên khác.") unless @oauth_attempt

    @attempts = attempts
    true
  end

  def step_load_provider_configuration
    @provider = @oauth_attempt.fetch("provider")
    @configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    @provider_configuration = @configuration.fetch(:providers).fetch(@provider.to_sym)
    return step_fail!("Callback của nhà cung cấp AI này không được hỗ trợ.") unless @provider_configuration.fetch(:enabled)

    true
  rescue KeyError
    step_fail!("Callback của nhà cung cấp AI này không được hỗ trợ.")
  end

  def step_consume_oauth_attempt
    allowed_uris = @provider_configuration.fetch(:allowed_redirect_uris)
    expected_uri = @provider_configuration.fetch(:redirect_uri)
    unless allowed_uris.include?(@callback_url) && expected_uri == @callback_url
      return step_fail!("Địa chỉ callback OAuth không hợp lệ.")
    end

    return step_fail!("OAuth state không khớp yêu cầu đăng nhập.") unless @oauth_attempt["state_digest"] == @state_digest
    return step_fail!("OAuth callback đã hết hạn.") unless Time.iso8601(@oauth_attempt.fetch("expires_at")) > Time.current
    return step_fail!("OAuth callback không khớp URI đã đăng ký.") unless @oauth_attempt.fetch("redirect_uri") == @callback_url

    @attempts.delete(@state_digest)
    @session["ai_provider_oauth_attempts"] = @attempts
    true
  rescue KeyError, ArgumentError
    step_fail!("OAuth callback đã hết hạn hoặc không hợp lệ.")
  end

  def step_validate_callback_result
    return step_fail!("Bạn đã hủy kết nối tài khoản AI.") if @params["error"].present?
    return step_fail!("Callback không trả authorization code.") if @params["code"].blank?

    true
  end

  def step_validate_returned_client_id
    if @provider == "gemini"
      @client_id = @oauth_attempt.fetch("client_id", @provider_configuration.fetch(:client_id))
      return true
    end

    @client_id = @oauth_attempt.fetch("client_id")
    if @provider == "codex"
      return step_fail!("OAuth callback không khớp client ID Codex đã cấu hình.") unless @client_id == @provider_configuration.fetch(:client_id)
      return step_fail!("Callback trả client ID khác với kết nối Codex.") if @params["client_id"].present? && @params["client_id"] != @client_id

      return true
    end

    returned_client_id = @params["client_id"].to_s
    if @client_id == @provider_configuration.fetch(:client_id)
      return step_fail!("OpenAI không trả issued client ID cho đăng ký mới.") if returned_client_id.blank? || returned_client_id == @client_id

      @client_id = returned_client_id
      return true
    end

    return step_fail!("Callback trả client ID khác với tài khoản đang kết nối.") if returned_client_id.present? && returned_client_id != @client_id

    true
  rescue KeyError
    step_fail!("OpenAI chưa cấu hình client ID đăng ký ban đầu.")
  end

  def step_exchange_code
    @client = if @provider == "openai"
      OpenAi::Client.new(configuration: @provider_configuration)
    elsif @provider == "codex"
      Codex::Client.new(configuration: @provider_configuration)
    else
      Gemini::Client.new(configuration: @provider_configuration)
    end
    @token_payload = if @provider == "openai"
      @client.exchange_code(
        code: @params.fetch("code"),
        client_id: @client_id,
        code_verifier: @oauth_attempt.fetch("code_verifier"),
        redirect_uri: @oauth_attempt.fetch("redirect_uri")
      )
    elsif @provider == "codex"
      @client.exchange_code(
        code: @params.fetch("code"),
        client_id: @client_id,
        code_verifier: @oauth_attempt.fetch("code_verifier"),
        redirect_uri: @oauth_attempt.fetch("redirect_uri")
      )
    else
      @client.exchange_code(
        code: @params.fetch("code"),
        code_verifier: @oauth_attempt.fetch("code_verifier"),
        redirect_uri: @oauth_attempt.fetch("redirect_uri")
      )
    end
    return step_fail!("Nhà cung cấp không trả đủ token để xác minh tài khoản.") if @token_payload["access_token"].blank? || @token_payload["id_token"].blank?

    true
  rescue OpenAi::Client::Error, Codex::Client::Error, Gemini::Client::Error, KeyError
    step_fail!("Không thể xác minh token OAuth. Hãy bắt đầu kết nối lại.")
  end

  def step_verify_identity
    @identity = if [ "openai", "codex" ].include?(@provider)
      identity_client = @provider == "codex" ? OpenAi::Client.new(configuration: @provider_configuration) : @client
      identity_client.verify_id_token(id_token: @token_payload.fetch("id_token"), client_id: @client_id)
    else
      @client.verify_id_token(@token_payload.fetch("id_token"))
    end
    @identity = @identity.deep_stringify_keys
    return step_fail!("Token OAuth không có định danh tài khoản hợp lệ.") if @identity["sub"].blank?

    true
  rescue OpenAi::Client::Error, Gemini::Client::Error, KeyError
    step_fail!("Không thể xác minh danh tính tài khoản AI.")
  end

  def step_validate_nonce
    return true unless @provider_configuration.fetch(:nonce_enabled, true)

    nonce_digest = Digest::SHA256.hexdigest(@identity["nonce"].to_s)
    return true if @identity["nonce"].present? && nonce_digest == @oauth_attempt["nonce_digest"]

    step_fail!("OAuth ID token không khớp nonce của phiên đăng nhập.")
  end

  def step_validate_selected_identity
    return true if @oauth_attempt["connection_id"].blank?

    connection = AiProviderConnection.find_by(id: @oauth_attempt.fetch("connection_id"))
    return true if connection&.provider == @provider &&
                   connection.provider_client_id == @client_id &&
                   connection.provider_subject == @identity["sub"]

    step_fail!("Tài khoản đã xác thực không trùng với kết nối cần đăng nhập lại.")
  end

  def step_load_models
    @granted_scopes = @token_payload.fetch("scope", "").split.uniq
    @required_scopes = @provider_configuration.fetch(:required_scopes)
    @available_models = []
    if @provider == "codex"
      @status = "pending_verification"
      step_succeed!
      return
    end

    @status = if (@required_scopes - @granted_scopes).any?
      "scope_missing"
    elsif @provider == "gemini"
      "pending_verification"
    else
      "ready"
    end
    return step_succeed! if @status == "scope_missing"

    @available_models = @client.list_models(access_token: @token_payload.fetch("access_token"))
    step_succeed!
  rescue OpenAi::Client::Error, Gemini::Client::Error, KeyError
    @available_models = []
    @status = "pending_verification"
    step_succeed!
  end

  def step_persist_connection
    @ai_provider_connection = step_connection_to_update
    return unless @ai_provider_connection

    previous_refresh_token = @ai_provider_connection.refresh_token
    selected_model = @ai_provider_connection.selected_model
    @ai_provider_connection.assign_attributes(
      provider: @provider,
      provider_subject: @identity.fetch("sub"),
      provider_client_id: @client_id,
      account_email: @identity["email"],
      display_name: @identity["name"],
      access_token: @token_payload.fetch("access_token"),
      refresh_token: @token_payload["refresh_token"].presence || previous_refresh_token,
      id_token: @token_payload.fetch("id_token"),
      access_token_expires_at: step_token_expiry,
      scopes: @granted_scopes,
      available_models: @available_models,
      selected_model: @available_models.any? { |model| model["slug"] == selected_model } ? selected_model : nil,
      last_verified_at: Time.current,
      status: @status
    )
    return step_succeed! if @ai_provider_connection.save

    step_fail!("Không thể lưu kết nối tài khoản AI đã xác minh.")
  end

  def step_connection_to_update
    if @oauth_attempt["connection_id"].present?
      connection = AiProviderConnection.find_by(id: @oauth_attempt.fetch("connection_id"))
      return connection if connection&.provider == @provider &&
                           connection.provider_client_id == @client_id &&
                           connection.provider_subject == @identity.fetch("sub")

      step_fail!("Kết nối tài khoản không còn tồn tại hoặc không khớp.")
      return
    end

    AiProviderConnection.find_or_initialize_by(
      provider: @provider,
      provider_client_id: @client_id,
      provider_subject: @identity.fetch("sub")
    )
  end

  def step_token_expiry
    expires_in = @token_payload["expires_in"].to_i
    expires_in.positive? ? Time.current + expires_in.seconds : nil
  end
end
