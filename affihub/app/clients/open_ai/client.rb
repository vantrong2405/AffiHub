require "jwt"

class OpenAi::Client
  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe provider error category
    # @return [OpenAi::Client::Error] the sanitized API error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Initializes the OpenAI account client with provider settings.
  #
  # @param configuration [Hash, nil] provider configuration or the configured OpenAI settings
  # @return [OpenAi::Client] the configured client
  def initialize(configuration: nil)
    @configuration = configuration || Rails.application.config_for(:ai_providers).deep_symbolize_keys.fetch(:providers).fetch(:openai)
  end

  # Exchanges a one-time registration or authorization code for account tokens.
  #
  # @param code [String] the authorization code returned to the loopback callback
  # @param client_id [String] the issued OpenAI client ID for this account
  # @param code_verifier [String] the PKCE verifier from the authorization attempt
  # @param redirect_uri [String] the exact loopback callback URI used to authorize
  # @return [Hash] the provider token response
  def exchange_code(code:, client_id:, code_verifier:, redirect_uri:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "authorization_code",
        code:,
        client_id:,
        code_verifier:,
        redirect_uri:,
        resource: @configuration.fetch(:resource)
      }
    )
  end

  # Verifies an OpenAI ID token against the provider's published JWKS and claims.
  #
  # @param id_token [String] the ID token returned by OpenAI
  # @param client_id [String] the issued account client ID expected in the audience
  # @return [Hash] the verified ID-token claims
  def verify_id_token(id_token:, client_id:)
    metadata = openid_configuration
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

  # Lists the account-specific models that OpenAI marks for display.
  #
  # @param access_token [String] the user's OpenAI access token
  # @return [Array<Hash>] the displayable account model catalog
  def list_models(access_token:)
    response = request(
      method: :get,
      endpoint: "#{@configuration.fetch(:api_base_url)}/models",
      headers: { "Authorization" => "Bearer #{access_token}" }
    )
    response.fetch("models", []).filter_map do |model|
      next unless model["visibility"] == @configuration.fetch(:model_visibility, "list")

      {
        "slug" => model.fetch("slug"),
        "display_name" => model.fetch("display_name"),
        "visibility" => model.fetch("visibility")
      }
    end
  end

  # Generates text through the public Responses API using a completed SSE stream.
  #
  # @param access_token [String] the user's OpenAI OAuth access token
  # @param model [String] a model slug returned for the connected account
  # @param input [String] the user-approved prompt for one text-generation step
  # @return [String] the completed output text
  def generate_text(access_token:, model:, input:)
    stream_state = { "buffer" => +"", "output_text" => +"", "completed" => false }
    request(
      method: :post,
      endpoint: "#{@configuration.fetch(:api_base_url)}/responses",
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Accept" => "text/event-stream"
      },
      body: {
        model:,
        input: [ { role: "user", content: [ { type: "input_text", text: input } ] } ],
        store: false,
        stream: true
      },
      body_type: :json,
      streaming: true
    ) do |chunk|
      step_consume_sse_chunk(stream_state, chunk)
    end
    step_process_sse_event(stream_state, stream_state.fetch("buffer")) if stream_state.fetch("buffer").present?
    raise Error, "response_not_completed" unless stream_state.fetch("completed")
    raise Error, "empty_response" if stream_state.fetch("output_text").blank?

    stream_state.fetch("output_text")
  end

  # Refreshes an OpenAI access token using its issued account client ID.
  #
  # @param refresh_token [String] the encrypted renewable credential
  # @param client_id [String] the issued client ID saved with this account
  # @return [Hash] the refreshed provider token response
  def refresh_token(refresh_token:, client_id:)
    request(
      method: :post,
      endpoint: @configuration.fetch(:token_endpoint),
      body: {
        grant_type: "refresh_token",
        refresh_token:,
        client_id:,
        resource: @configuration.fetch(:resource)
      }
    )
  end

  # Revokes the renewable OpenAI account session through discovered OIDC metadata.
  #
  # @param refresh_token [String] the renewable credential to revoke
  # @param client_id [String] the issued client ID saved with the account
  # @return [Boolean] whether the provider confirmed revocation
  def revoke_token(refresh_token:, client_id:)
    revocation_endpoint = openid_configuration.fetch("revocation_endpoint")
    request(
      method: :post,
      endpoint: revocation_endpoint,
      body: {
        token: refresh_token,
        token_type_hint: "refresh_token",
        client_id:
      }
    )
    true
  end

  private

  def openid_configuration
    @openid_configuration ||= request(
      method: :get,
      endpoint: @configuration.fetch(:openid_configuration_endpoint)
    )
  end

  def request(method:, endpoint:, headers: {}, body: nil, body_type: :form, streaming: false)
    uri = URI(endpoint)
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri)
    headers.each { |name, value| http_request[name] = value }
    if body
      if body_type == :json
        http_request["Content-Type"] = "application/json"
        http_request.body = JSON.generate(body)
      else
        http_request["Content-Type"] = "application/x-www-form-urlencoded"
        http_request.body = URI.encode_www_form(body)
      end
    end
    response = nil
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: @configuration.fetch(:connect_timeout_seconds),
      read_timeout: @configuration.fetch(:read_timeout_seconds)
    ) do |http|
      if streaming
        http.request(http_request) do |stream_response|
          response = stream_response
          raise Error, step_safe_http_error(response) unless response.is_a?(Net::HTTPSuccess)

          stream_response.read_body { |chunk| yield chunk if block_given? }
        end
      else
        response = http.request(http_request)
      end
    end
    raise Error, step_safe_http_error(response) unless response.is_a?(Net::HTTPSuccess)

    return {} if streaming

    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError
    raise Error, "invalid_endpoint"
  end

  def step_safe_http_error(response)
    parsed_response = JSON.parse(response.body.presence || "{}")
    provider_error = parsed_response["error"]
    provider_code = provider_error.is_a?(Hash) ? provider_error["code"] : provider_error
    return provider_code if provider_code.to_s.match?(/\A[a-zA-Z0-9_.-]+\z/)

    "http_#{response.code}"
  rescue JSON::ParserError
    "http_#{response.code}"
  end

  def step_consume_sse_chunk(stream_state, chunk)
    stream_state.fetch("buffer") << chunk
    loop do
      boundary = /\r?\n\r?\n/.match(stream_state.fetch("buffer"))
      break unless boundary

      event_frame = stream_state.fetch("buffer").slice!(0, boundary.end(0))
      step_process_sse_event(stream_state, event_frame)
    end
  end

  def step_process_sse_event(stream_state, event_frame)
    event_type = nil
    event_data = []
    event_frame.each_line do |line|
      normalized_line = line.chomp
      event_type = normalized_line.delete_prefix("event:").strip if normalized_line.start_with?("event:")
      event_data << normalized_line.delete_prefix("data:").strip if normalized_line.start_with?("data:")
    end
    return if event_data.empty? || event_data == [ "[DONE]" ]

    event = JSON.parse(event_data.join("\n"))
    case event_type || event["type"]
    when "response.output_text.delta"
      stream_state.fetch("output_text") << event.fetch("delta")
    when "response.completed"
      stream_state["completed"] = true
    when "response.failed"
      raise Error, step_safe_provider_error(event.dig("response", "error", "code"))
    when "response.incomplete"
      raise Error, "response_incomplete"
    end
  rescue JSON::ParserError, KeyError
    raise Error, "invalid_stream_event"
  end

  def step_safe_provider_error(code)
    return "response_failed" unless code.to_s.match?(/\A[a-zA-Z0-9_.-]+\z/)

    code.to_s
  end
end
