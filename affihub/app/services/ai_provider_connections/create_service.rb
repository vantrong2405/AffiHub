class AiProviderConnections::CreateService < ApplicationService
  attr_reader :authorization_url, :state

  # Initializes an OAuth flow using the caller's browser session.
  #
  # @param provider [String, Symbol] the AI provider to connect
  # @param session [ActionDispatch::Request::Session, Hash] the browser session
  # @param ai_provider_connection_id [String, Integer, nil] an account to reauthorize
  # @param request_origin [String, nil] the browser origin that initiated the flow
  # @return [AiProviderConnections::CreateService] the configured service
  def initialize(provider:, session:, ai_provider_connection_id: nil, request_origin: nil)
    @provider = provider.to_s
    @session = session
    @ai_provider_connection_id = ai_provider_connection_id
    @request_origin = request_origin
    super()
  end

  # Creates a one-time provider authorization request bound to this session.
  #
  # @return [Boolean] whether the authorization URL was created
  def call
    return false unless step_load_provider_configuration
    return false unless step_validate_provider
    return false unless step_load_reauthorization_connection
    return false unless step_validate_oauth_configuration

    step_create_authorization_request
    success?
  end

  private

  def step_load_provider_configuration
    @configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    @provider_configuration = @configuration.fetch(:providers).fetch(@provider.to_sym)
    true
  rescue KeyError
    step_fail!("Nhà cung cấp AI này chưa được hỗ trợ.")
  end

  def step_validate_provider
    return true if @provider_configuration.fetch(:enabled)

    message = if @provider == "antigravity"
      "#{@provider_configuration.fetch(:display_name)} chưa được phép kết nối với AffiHub."
    else
      "Kết nối với nhà cung cấp AI này hiện chưa khả dụng."
    end
    step_fail!(message)
  end

  def step_load_reauthorization_connection
    return true if @ai_provider_connection_id.blank?

    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
    return true if @ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI cần đăng nhập lại.")
  end

  def step_validate_oauth_configuration
    redirect_uri = @provider_configuration.fetch(:redirect_uri)
    allowed_uris = @provider_configuration.fetch(:allowed_redirect_uris)
    return step_fail!("Callback OAuth chưa nằm trong danh sách được phép.") unless allowed_uris.include?(redirect_uri)
    return false unless step_validate_request_origin(redirect_uri)

    return false unless step_validate_required_configuration

    if @ai_provider_connection && @ai_provider_connection.provider != @provider
      return step_fail!("Kết nối tài khoản không khớp với nhà cung cấp đã chọn.")
    end

    true
  end

  def step_validate_request_origin(redirect_uri)
    return true if @request_origin.blank?
    return true if step_uri_origin(redirect_uri) == step_uri_origin(@request_origin)

    step_fail!("Mở AffiHub tại #{step_uri_origin(redirect_uri)} để kết nối tài khoản này.")
  rescue URI::InvalidURIError
    step_fail!("Origin OAuth không hợp lệ.")
  end

  def step_uri_origin(value)
    uri = URI(value)
    raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.userinfo.nil?

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end

  def step_validate_required_configuration
    requirements = @provider_configuration.fetch(:configuration_requirements, {})
    shared_keys = requirements.fetch(:shared, []).map(&:to_sym)
    provider_keys = requirements.fetch(:provider, []).map(&:to_sym)
    shared_missing = shared_keys.any? { |key| @configuration.fetch(key).blank? }
    provider_missing = provider_keys.any? { |key| @provider_configuration.fetch(key).blank? }
    return true unless shared_missing || provider_missing

    message = case @provider
    when "codex"
      "Chưa cấu hình OAuth client ID cho #{@provider_configuration.fetch(:display_name)}."
    when "gemini"
      "Chưa cấu hình đầy đủ OAuth và Google Cloud project cho #{@provider_configuration.fetch(:display_name)}."
    else
      "Chưa cấu hình OAuth cho nhà cung cấp AI này."
    end
    step_fail!(message)
  end

  def step_create_authorization_request
    @state = SecureRandom.urlsafe_base64(32)
    nonce = step_nonce
    state_digest = Digest::SHA256.hexdigest(@state)
    attempt = {
      "provider" => @provider,
      "redirect_uri" => @provider_configuration.fetch(:redirect_uri),
      "state_digest" => state_digest,
      "expires_at" => (Time.current + @configuration.fetch(:oauth_state_ttl_seconds).seconds).iso8601(6),
      "client_id" => step_client_id,
      "connection_id" => @ai_provider_connection&.id
    }
    attempt["nonce_digest"] = Digest::SHA256.hexdigest(nonce) if nonce
    authorization_params = {
      client_id: attempt.fetch("client_id"),
      redirect_uri: attempt.fetch("redirect_uri"),
      response_type: "code",
      scope: @provider_configuration.fetch(:scopes).join(" "),
      state: @state
    }
    authorization_params[:nonce] = nonce if nonce
    step_add_pkce(authorization_params, attempt)
    step_add_provider_parameters(authorization_params)
    attempts = @session["ai_provider_oauth_attempts"] || {}
    attempts[state_digest] = attempt
    @session["ai_provider_oauth_attempts"] = attempts
    @authorization_url = "#{@provider_configuration.fetch(:authorization_endpoint)}?#{URI.encode_www_form(authorization_params)}"
    step_succeed!
  end

  def step_client_id
    return @ai_provider_connection.provider_client_id if @ai_provider_connection

    @provider_configuration.fetch(:client_id)
  end

  def step_nonce
    return unless @provider_configuration.fetch(:nonce_enabled)

    SecureRandom.urlsafe_base64(32)
  end

  def step_add_pkce(authorization_params, attempt)
    return unless @provider_configuration.fetch(:pkce_enabled)

    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    attempt["code_verifier"] = verifier
    authorization_params[:code_challenge] = challenge
    authorization_params[:code_challenge_method] = "S256"
  end

  def step_add_provider_parameters(authorization_params)
    return if @ai_provider_connection && @provider_configuration.fetch(:authorization_new_connection_only, false)

    @provider_configuration.fetch(:authorization_extra_parameters, {}).each do |key, value|
      authorization_params[key.to_sym] = value.to_s
    end
    @provider_configuration.fetch(:authorization_shared_parameters, {}).each do |key, source|
      authorization_params[key.to_sym] = @configuration.fetch(source.to_sym).to_s
    end
  end
end
