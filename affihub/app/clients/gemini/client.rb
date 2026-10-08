require "googleauth/id_tokens"

class Gemini::Client
  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe provider error category
    # @return [Gemini::Client::Error] the sanitized API error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Initializes the Gemini API client with Google OAuth and project settings.
  #
  # @param configuration [Hash, nil] provider configuration or the configured Gemini settings
  # @return [Gemini::Client] the configured client
  def initialize(configuration: nil)
    @configuration = configuration || Rails.application.config_for(:ai_providers).deep_symbolize_keys.fetch(:providers).fetch(:gemini)
  end

  # Exchanges a Google authorization code for Gemini API account tokens.
  #
  # @param code [String] the single-use Google authorization code
  # @param code_verifier [String] the PKCE verifier from the authorization attempt
  # @param redirect_uri [String] the exact Google OAuth callback URI used to authorize
  # @return [Hash] the provider token response
  def exchange_code(code:, code_verifier:, redirect_uri:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "authorization_code",
        client_id: @configuration.fetch(:client_id),
        client_secret: @configuration.fetch(:client_secret),
        code:,
        redirect_uri:,
        code_verifier:
      }
    )
  end

  # Verifies a Google ID token through the Google Auth Ruby library.
  #
  # @param id_token [String] the ID token returned by Google
  # @return [Hash] the verified ID-token claims
  def verify_id_token(id_token)
    Google::Auth::IDTokens.verify_oidc(id_token, aud: @configuration.fetch(:client_id)).stringify_keys
  rescue Google::Auth::IDTokens::KeySourceError, Google::Auth::IDTokens::VerificationError
    raise Error, "invalid_id_token"
  end

  # Lists Gemini models that support text generation for the configured project.
  #
  # @param access_token [String] the user's Google access token
  # @return [Array<Hash>] the Gemini model catalog for script and scene generation
  def list_models(access_token:)
    response = request(
      method: :get,
      endpoint: "#{@configuration.fetch(:api_base_url)}/models",
      headers: {
        "Authorization" => "Bearer #{access_token}",
        @configuration.fetch(:user_project_header) => @configuration.fetch(:project_id)
      }
    )
    response.fetch("models", []).filter_map do |model|
      next unless model.fetch("supportedGenerationMethods", []).include?("generateContent")

      { "slug" => model.fetch("name"), "display_name" => model.fetch("displayName") }
    end
  end

  # Refreshes a Google access token for the configured Gemini OAuth client.
  #
  # @param refresh_token [String] the encrypted renewable Google credential
  # @return [Hash] the refreshed provider token response
  def refresh_token(refresh_token:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "refresh_token",
        refresh_token:,
        client_id: @configuration.fetch(:client_id),
        client_secret: @configuration.fetch(:client_secret)
      }
    )
  end

  # Revokes a Google OAuth token using the documented revocation endpoint.
  #
  # @param refresh_token [String] the renewable credential to revoke
  # @return [Boolean] whether Google confirmed revocation
  def revoke_token(refresh_token:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:revocation_endpoint),
      body: { token: refresh_token }
    )
    true
  end

  private

  def request(method:, endpoint:, headers: {}, body: nil)
    uri = URI(endpoint)
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri)
    headers.each { |name, value| http_request[name] = value }
    if body
      http_request["Content-Type"] = "application/x-www-form-urlencoded"
      http_request.body = URI.encode_www_form(body)
    end
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: @configuration.fetch(:connect_timeout_seconds),
      read_timeout: @configuration.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    unless response.is_a?(Net::HTTPSuccess)
      error_code = provider_error_code(response.body)
      raise Error, error_code || "http_#{response.code}"
    end

    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError
    raise Error, "invalid_endpoint"
  end

  def provider_error_code(response_body)
    payload = JSON.parse(response_body.presence || "{}")
    error_code = payload["error"]
    error_code = error_code["status"] if error_code.is_a?(Hash)
    return error_code if %w[invalid_grant invalid_client invalid_scope access_denied].include?(error_code)

    nil
  rescue JSON::ParserError
    nil
  end
end
