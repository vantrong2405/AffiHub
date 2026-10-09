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
    @provider_configuration = SocialConnections::ProviderConfiguration.for(@provider)
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
    @token_payload = oauth_client.exchange_code(
      code: @params.fetch("code"),
      redirect_uri: @oauth_attempt.fetch("redirect_uri"),
      code_verifier: @oauth_attempt["code_verifier"]
    )
    return true if @token_payload["access_token"].present?

    step_fail!("Nền tảng không trả access token cho kết nối này.")
  rescue Meta::Client::Error, TikTok::Client::Error, Youtube::Client::Error
    step_fail!("Nền tảng chưa thể xác nhận kết nối. Hãy thử bắt đầu lại.")
  end

  def step_load_profile
    @profile = oauth_client.profile(access_token: @token_payload.fetch("access_token"))
    return true if profile_external_id.present? && profile_name.present?

    step_fail!("Nền tảng không trả thông tin profile hợp lệ.")
  rescue Meta::Client::Error, TikTok::Client::Error, Youtube::Client::Error
    step_fail!("Không thể đọc profile sau khi xác thực.")
  end

  def step_persist_connection
    SocialConnection.transaction do
      @social_connection = SocialConnection.find_or_initialize_by(
        provider: @provider,
        external_user_id: profile_external_id
      )
      @social_connection.assign_attributes(
        name: profile_name,
        access_token: @token_payload.fetch("access_token"),
        token_expires_at: token_expiry,
        refresh_token: @token_payload["refresh_token"].presence || @social_connection.refresh_token,
        refresh_token_expires_at: token_expiry("refresh_expires_in") || @social_connection.refresh_token_expires_at,
        scopes: token_scopes.presence || @social_connection.scopes,
        status: :connected
      )
      @social_connection.save!
      step_persist_tiktok_destination if @provider == "tiktok"
    end
    step_succeed!
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu kết nối và đích đăng của nền tảng.")
  end

  def step_persist_tiktok_destination
    destination = @social_connection.social_destinations.find_or_initialize_by(external_id: profile_external_id)
    destination.assign_attributes(
      provider: @provider,
      name: profile_name,
      access_token: @social_connection.access_token,
      token_expires_at: @social_connection.token_expires_at,
      status: :connected,
      metadata: { "authorized_scopes" => @social_connection.scopes }
    )
    destination.save!
  end

  def oauth_client
    case @provider
    when "tiktok" then TikTok::Client.new
    when "youtube" then Youtube::Client.new
    else Meta::Client.new(provider: @provider)
    end
  end

  def profile_external_id
    field = @provider_configuration.fetch(:profile_id_field, @provider == "tiktok" ? "open_id" : "id")
    @profile&.fetch(field.to_s, nil)
  end

  def profile_name
    field = @provider_configuration.fetch(:profile_name_field, @provider == "tiktok" ? "display_name" : "name")
    @profile&.fetch(field.to_s, nil)
  end

  def token_scopes
    @token_payload.fetch("scope", "").split(",").map(&:strip).reject(&:blank?).uniq
  end

  def token_expiry(field = "expires_in")
    expires_in = @token_payload[field].to_i
    expires_in.positive? ? Time.current + expires_in.seconds : nil
  end
end
