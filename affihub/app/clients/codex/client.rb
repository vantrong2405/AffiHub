class Codex::Client
  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe provider error category
    # @return [Codex::Client::Error] the sanitized API error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Initializes the Codex OAuth client with provider settings.
  #
  # @param configuration [Hash, nil] provider settings or configured Codex OAuth settings
  # @return [Codex::Client] the configured client
  def initialize(configuration: nil)
    @configuration = configuration || Rails.application.config_for(:ai_providers).deep_symbolize_keys.fetch(:providers).fetch(:codex)
  end

  # Exchanges an authorization code using the saved PKCE verifier.
  #
  # @param code [String] the one-time authorization code
  # @param client_id [String] the configured Codex OAuth client ID
  # @param code_verifier [String] the verifier from the authorization attempt
  # @param redirect_uri [String] the fixed loopback callback used for authorization
  # @return [Hash] the OAuth token response
  def exchange_code(code:, client_id:, code_verifier:, redirect_uri:)
    request(
      grant_type: "authorization_code",
      client_id:,
      code:,
      redirect_uri:,
      code_verifier:
    )
  end

  # Refreshes the Codex OAuth tokens with the configured public client ID.
  #
  # @param refresh_token [String] the encrypted renewable credential
  # @param client_id [String] the configured Codex OAuth client ID
  # @return [Hash] the OAuth token response
  def refresh_token(refresh_token:, client_id:)
    request(
      grant_type: "refresh_token",
      client_id:,
      refresh_token:
    )
  end

  private

  def request(body)
    uri = URI(@configuration.fetch(:token_endpoint))
    http_request = Net::HTTP::Post.new(uri)
    http_request["Accept"] = "application/json"
    http_request["Content-Type"] = "application/x-www-form-urlencoded"
    http_request.body = URI.encode_www_form(body)

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: @configuration.fetch(:connect_timeout_seconds),
      read_timeout: @configuration.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    raise Error, step_safe_error_code(response) unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError
    raise Error, "invalid_endpoint"
  end

  def step_safe_error_code(response)
    parsed_response = JSON.parse(response.body.presence || "{}")
    provider_error = parsed_response["error"]
    provider_code = provider_error.is_a?(Hash) ? provider_error["code"] : provider_error
    return provider_code if provider_code.to_s.match?(/\A[a-zA-Z0-9_.-]+\z/)

    "http_#{response.code}"
  rescue JSON::ParserError
    "http_#{response.code}"
  end
end
