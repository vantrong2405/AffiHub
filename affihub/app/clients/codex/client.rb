require "jwt"

class Codex::Client
  class Error < AiProviderClientError
  end

  # Initializes the Codex OAuth client with provider settings.
  #
  # @param configuration [Hash, nil] provider settings or configured Codex OAuth settings
  # @return [Codex::Client] the configured client
  def initialize(configuration: nil)
    @configuration = configuration || AiProviderConfiguration.for_client(client_class_name: self.class.name)
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
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "authorization_code",
        client_id:,
        code:,
        redirect_uri:,
        code_verifier:
      }
    )
  end

  # Refreshes the Codex OAuth tokens with the configured public client ID.
  #
  # @param refresh_token [String] the encrypted renewable credential
  # @param client_id [String] the configured Codex OAuth client ID
  # @return [Hash] the OAuth token response
  def refresh_token(refresh_token:, client_id:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "refresh_token",
        client_id:,
        refresh_token:
      }
    )
  end

  # Verifies a Codex ID token against OpenAI's published OIDC keys and claims.
  #
  # @param id_token [String] the ID token returned by the Codex OAuth flow
  # @param client_id [String] the configured Codex OAuth client ID
  # @return [Hash] the verified ID-token claims
  def verify_id_token(id_token:, client_id:)
    metadata = request(
      method: :get,
      endpoint: @configuration.fetch(:openid_configuration_endpoint)
    )
    issuer = metadata.fetch("issuer")
    raise Error, "invalid_openid_issuer" unless issuer == "https://auth.openai.com"

    jwks_uri = URI(metadata.fetch("jwks_uri"))
    unless jwks_uri.is_a?(URI::HTTPS) && jwks_uri.host == "auth.openai.com" && jwks_uri.userinfo.nil?
      raise Error, "invalid_jwks_uri"
    end

    jwks = JWT::JWK::Set.new(request(method: :get, endpoint: jwks_uri.to_s))
    claims, = JWT.decode(
      id_token,
      nil,
      true,
      algorithms: [ "RS256" ],
      jwks:,
      iss: issuer,
      verify_iss: true,
      aud: client_id,
      verify_aud: true
    )
    claims.stringify_keys
  rescue KeyError, URI::InvalidURIError, JWT::DecodeError, JWT::JWKError
    raise Error, "invalid_id_token"
  end

  private

  def request(method:, endpoint:, body: nil)
    uri = URI(endpoint)
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri)
    http_request["Accept"] = "application/json"
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
