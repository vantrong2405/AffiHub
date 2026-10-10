class SocialConnections::CreateService < ApplicationService
  attr_reader :authorization_url, :state

  # Initializes a Facebook OAuth flow using the caller's browser session.
  #
  # @param provider [String, Symbol] the social provider to connect
  # @param session [ActionDispatch::Request::Session, Hash] the browser session
  # @return [SocialConnections::CreateService] the configured service
  def initialize(provider:, session:)
    @provider = provider.to_s
    @session = session
    super()
  end

  # Creates a one-time authorization request bound to this browser session.
  #
  # @return [Boolean] whether the authorization URL was created
  def call
    return false unless step_load_provider_configuration
    return false unless step_validate_oauth_configuration

    step_create_authorization_request
    success?
  end

  private

  def step_load_provider_configuration
    @provider_configuration = SocialConnections::ProviderConfiguration.for(@provider)
    true
  rescue KeyError
    step_fail!("Nền tảng này chưa được cấu hình kết nối.")
  end

  def step_validate_oauth_configuration
    allowed_uris = @provider_configuration.fetch(:allowed_redirect_uris)
    redirect_uri = @provider_configuration.fetch(:redirect_uri)
    return step_fail!("Callback OAuth chưa nằm trong danh sách được phép.") unless allowed_uris.include?(redirect_uri)
    return step_fail!("Chưa cấu hình OAuth client cho nền tảng này.") if @provider_configuration.fetch(:client_id).blank?
    return step_fail!("Chưa cấu hình đầy đủ quyền kết nối cho nền tảng này.") if missing_authorization_parameter?

    true
  end

  def missing_authorization_parameter?
    required_parameters = @provider_configuration.fetch(:required_authorization_parameters, [])
    authorization_params = @provider_configuration.fetch(:authorization_params, {})
    required_parameters.any? { |parameter| authorization_params[parameter].blank? }
  end

  def step_create_authorization_request
    @state = SecureRandom.urlsafe_base64(32)
    digest = Digest::SHA256.hexdigest(@state)
    attempt = {
      "provider" => @provider,
      "redirect_uri" => @provider_configuration.fetch(:redirect_uri),
      "expires_at" => (Time.current + oauth_state_ttl).iso8601(6)
    }
    authorization_params = {
      @provider_configuration.fetch(:authorization_client_parameter, :client_id) => @provider_configuration.fetch(:client_id),
      redirect_uri: attempt.fetch("redirect_uri"),
      response_type: "code",
      state: @state
    }
    step_add_scopes(authorization_params)
    authorization_params.merge!(@provider_configuration.fetch(:authorization_params, {}))
    step_add_pkce(authorization_params, attempt)
    attempts = @session["social_oauth_attempts"] || {}
    attempts[digest] = attempt
    @session["social_oauth_attempts"] = attempts
    base_url = @provider_configuration.fetch(:authorization_base_url)
    authorization_path = if @provider_configuration.key?(:authorization_path)
      @provider_configuration.fetch(:authorization_path)
    else
      "/#{@provider_configuration.fetch(:api_version)}/dialog/oauth"
    end
    authorization_uri = URI.join("#{base_url}/", authorization_path).to_s
    @authorization_url = "#{authorization_uri}?#{URI.encode_www_form(authorization_params)}"
    step_succeed!
  end

  def step_add_scopes(authorization_params)
    return true unless @provider_configuration.fetch(:include_scopes_in_authorization_request, true)

    authorization_params[:scope] = @provider_configuration.fetch(:scopes).join(
      @provider_configuration.fetch(:scope_separator, ",")
    )
    true
  end

  def step_add_pkce(authorization_params, attempt)
    return unless @provider_configuration.fetch(:pkce_enabled)

    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    attempt["code_verifier"] = verifier
    authorization_params[:code_challenge] = challenge
    authorization_params[:code_challenge_method] = "S256"
  end

  def oauth_state_ttl
    @provider_configuration.fetch(
      :oauth_state_ttl_seconds,
      Rails.application.config_for(:meta).fetch(:oauth_state_ttl_seconds)
    ).seconds
  end
end
