class GoogleConnections::CreateService < ApplicationService
  attr_reader :authorization_url, :state

  # Initializes a Google Drive or Sheets OAuth request bound to the browser session.
  #
  # @param integration [String, Symbol] the Google integration to connect
  # @param session [ActionDispatch::Request::Session, Hash] the caller's browser session
  # @return [GoogleConnections::CreateService] the configured service
  def initialize(integration:, session:)
    @integration = integration.to_s
    @session = session
    super()
  end

  # Creates a one-time Google authorization URL with the selected integration's scopes.
  #
  # @return [Boolean] whether the authorization request was created
  def call
    return false unless step_load_configuration
    return false unless step_validate_configuration

    step_create_authorization_request
    success?
  end

  private

  def step_load_configuration
    @configuration = Rails.application.config_for(:google).deep_symbolize_keys
    @oauth_configuration = @configuration.fetch(:oauth)
    @integration_configuration = @oauth_configuration.fetch(:integrations).fetch(@integration.to_sym)
    true
  rescue KeyError
    step_fail!("Dịch vụ Google này chưa được cấu hình.")
  end

  def step_validate_configuration
    redirect_uri = @oauth_configuration.fetch(:redirect_uri)
    allowed_redirect_uris = @oauth_configuration.fetch(:allowed_redirect_uris)
    return step_fail!("Callback Google chưa nằm trong danh sách được phép.") unless allowed_redirect_uris.include?(redirect_uri)
    return step_fail!("Chưa cấu hình OAuth client cho Google.") if @oauth_configuration.fetch(:client_id).blank?

    true
  end

  def step_create_authorization_request
    @state = SecureRandom.urlsafe_base64(32)
    state_digest = Digest::SHA256.hexdigest(@state)
    code_verifier = SecureRandom.urlsafe_base64(64)
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    redirect_uri = @oauth_configuration.fetch(:redirect_uri)
    attempt = {
      "integration" => @integration,
      "redirect_uri" => redirect_uri,
      "expires_at" => (Time.current + @configuration.fetch(:oauth_state_ttl_seconds).seconds).iso8601(6),
      "code_verifier" => code_verifier
    }
    authorization_parameters = {
      client_id: @oauth_configuration.fetch(:client_id),
      redirect_uri:,
      response_type: "code",
      scope: @integration_configuration.fetch(:scopes).join(" "),
      state: @state,
      access_type: "offline",
      code_challenge:,
      code_challenge_method: "S256"
    }
    attempts = @session["google_oauth_attempts"] || {}
    attempts[state_digest] = attempt
    @session["google_oauth_attempts"] = attempts
    @authorization_url = "#{@oauth_configuration.fetch(:authorization_url)}?#{URI.encode_www_form(authorization_parameters)}"
    step_succeed!
  end
end
