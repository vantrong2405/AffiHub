# frozen_string_literal: true

require "net/http"
require "json"
require "timeout"

# PORO wrapping the unofficial Codex CLI OAuth/PKCE flow against auth.openai.com and the
# unofficial chatgpt.com/backend-api/codex/responses endpoint. See
# docs/reference-analysis/ai-connection.md for the ported behavior and risk notes. All
# endpoints/ids/headers below are verified against decolua/9router's real provider registry
# (open-sse/providers/registry/codex.js), not invented — see that doc for the exact source read.
class CodexClient
  CONFIG = Rails.application.config_for(:codex)
  REDIRECT_URI = URI::Generic.build(
    scheme: "http",
    host: CONFIG.callback_host,
    port: CONFIG.callback_port,
    path: CONFIG.callback_path
  ).to_s

  class TokenExchangeError < StandardError; end
  class InvalidRefreshTokenError < TokenExchangeError; end
  class TransportError < StandardError; end
  class PromptRequestError < StandardError; end

  # Builds the auth.openai.com authorize URL for the OAuth/PKCE flow.
  #
  # @param state [String] opaque value echoed back on callback, checked for CSRF protection
  # @param code_challenge [String] PKCE S256 code_challenge derived from the caller's code_verifier
  # @return [String] the full https://auth.openai.com/oauth/authorize URL to redirect the user to
  def build_authorize_url(state:, code_challenge:)
    uri = URI(CONFIG.authorize_url)
    uri.query = URI.encode_www_form(
      {
        client_id: CONFIG.client_id,
        redirect_uri: REDIRECT_URI,
        scope: CONFIG.scope,
        response_type: "code",
        code_challenge_method: CONFIG.code_challenge_method,
        code_challenge: code_challenge
      }.merge(CONFIG.extra_authorize_params).merge(state: state)
    )
    uri.to_s
  end

  # Exchanges an authorization code for access_token/refresh_token/id_token/expires_in.
  #
  # @param code [String] the authorization code received at the /auth/callback redirect
  # @param code_verifier [String] the PKCE code_verifier used to build the original code_challenge
  # @return [Hash] parsed token response ("access_token", "refresh_token", "id_token", "expires_in")
  # @raise [CodexClient::TokenExchangeError] if auth.openai.com rejects the exchange
  def exchange_token(code:, code_verifier:)
    post_token(
      grant_type: "authorization_code",
      code: code,
      code_verifier: code_verifier,
      redirect_uri: REDIRECT_URI,
      client_id: CONFIG.client_id
    )
  end

  # Rotates the refresh_token: returns a NEW access_token/refresh_token/expires_in.
  #
  # @param refresh_token [String] the current refresh_token to exchange
  # @return [Hash] parsed token response ("access_token", "refresh_token", "expires_in")
  # @raise [CodexClient::TokenExchangeError] if the refresh_token was already rotated/revoked
  def refresh_token(refresh_token:)
    post_token(
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: CONFIG.client_id,
      scope: CONFIG.scope
    )
  end

  # Fetches the issuer's JSON Web Key Set for ID token signature verification.
  #
  # @return [Hash] parsed JWKS document from the configured issuer
  # @raise [CodexClient::TokenExchangeError] if the issuer returns an invalid JWKS response
  def fetch_jwks
    response = request(CONFIG.jwks_url, method: :get, headers: { "Accept" => "application/json" })
    raise TokenExchangeError, "auth.openai.com JWKS endpoint returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise TokenExchangeError, "auth.openai.com JWKS endpoint returned invalid JSON"
  end

  # Sends a real prompt to the unofficial ChatGPT backend-api, impersonating the Codex CLI.
  #
  # @param access_token [String] a fresh (non-expired) Codex access_token
  # @param chatgpt_account_id [String, nil] the ChatGPT account id to attribute the request to
  # @param prompt [String] the prompt text to send
  # @return [Hash] response with the accumulated output_text from the SSE stream
  # @raise [CodexClient::PromptRequestError] if chatgpt.com returns a non-2xx response
  def send_prompt(access_token:, chatgpt_account_id:, prompt:)
    response = post_json(
      CONFIG.responses_url,
      body: {
        model: CONFIG.model,
        input: [ { role: "user", content: [ { type: "input_text", text: prompt } ] } ],
        stream: true,
        store: false
      },
      headers: cli_impersonation_headers.merge(
        "Authorization" => "Bearer #{access_token}",
        "chatgpt-account-id" => chatgpt_account_id,
        "Accept" => "text/event-stream"
      )
    )
    raise PromptRequestError, "chatgpt.com returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    stream = parse_response_stream(response.body)
    unless stream[:completed] && !stream[:failed] && stream[:output_text].present?
      raise PromptRequestError, "chatgpt.com returned an incomplete or empty response stream"
    end

    { "output_text" => stream[:output_text] }
  end

  private

  # Builds a token exchange request and parses the JSON response.
  #
  # @param params [Hash] form-encoded grant params (authorization_code or refresh_token grant)
  # @return [Hash] parsed token response
  # @raise [CodexClient::TokenExchangeError] on any non-2xx response
  def post_token(params)
    response = request(CONFIG.token_url, body: params, body_format: :form)
    unless response.is_a?(Net::HTTPSuccess)
      error_code = JSON.parse(response.body).fetch("error", nil)
      error_class = params[:grant_type] == "refresh_token" && %w[invalid_grant invalid_token].include?(error_code) ? InvalidRefreshTokenError : TokenExchangeError
      raise error_class, "auth.openai.com token endpoint returned #{response.code}"
    end

    token_response = JSON.parse(response.body)
    validate_token_response!(token_response, params[:grant_type])
    token_response
  rescue JSON::ParserError
    raise TokenExchangeError, "auth.openai.com token endpoint returned invalid JSON"
  end

  # Builds a JSON prompt request and delegates network I/O to the shared transport.
  #
  # @param url [String] absolute URL to POST to
  # @param body [Hash] request body, JSON-encoded
  # @param headers [Hash<String, String>] extra headers to set on the request
  # @return [Net::HTTPResponse] the raw response
  def post_json(url, body:, headers: {})
    request(url, body: body, headers: headers, body_format: :json)
  end

  # Parses output deltas and terminal states from a Codex Responses SSE body.
  #
  # @param body [String] the complete server-sent events response
  # @return [Hash] accumulated output text and completion/error flags
  def parse_response_stream(body)
    result = { output_text: +"", completed: false, failed: false }

    body.each_line do |line|
      next unless line.start_with?("data: ")

      event_data = line.delete_prefix("data: ").strip
      next if event_data == "[DONE]"

      event = JSON.parse(event_data)
      case event["type"]
      when "response.output_text.delta"
        result[:output_text] << event["delta"] if event["delta"].is_a?(String)
      when "response.completed"
        result[:completed] = true
      when "error", "response.failed", "response.incomplete"
        result[:failed] = true
      end
    rescue JSON::ParserError
      result[:failed] = true
    end

    result
  end

  # Sends a POST request using the configured timeout values and selected body encoding.
  #
  # @param url [String] absolute request URL
  # @param body [Hash] request payload
  # @param headers [Hash<String, String>] request headers
  # @param body_format [Symbol] :form for URL-encoded data or :json for JSON data
  # @return [Net::HTTPResponse] the raw response
  def request(url, method: :post, body: nil, headers: {}, body_format: nil)
    uri = URI(url)
    http_request = build_http_request(uri, method)
    http_request["Content-Type"] = body_content_type(body_format) if body_format
    headers.each { |key, value| http_request[key] = value }
    http_request.body = encode_body(body, body_format) if body_format

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIG.open_timeout,
      read_timeout: CONFIG.read_timeout,
      write_timeout: CONFIG.write_timeout
    ) { |http| http.request(http_request) }
  rescue Timeout::Error, SocketError, SystemCallError, EOFError, IOError, OpenSSL::SSL::SSLError => error
    raise TransportError, error.class.name
  end

  # Builds a supported HTTP request for the shared transport.
  #
  # @param uri [URI::Generic] configured absolute request URL
  # @param method [Symbol] request method, currently :get or :post
  # @return [Net::HTTPRequest] request object for the shared transport
  def build_http_request(uri, method)
    case method
    when :get then Net::HTTP::Get.new(uri)
    when :post then Net::HTTP::Post.new(uri)
    else raise ArgumentError, "Unsupported HTTP method: #{method}"
    end
  end

  # Encodes a request payload according to its selected format.
  #
  # @param body [Hash] request payload
  # @param format [Symbol] :form or :json
  # @return [String] encoded request body
  def encode_body(body, format)
    case format
    when :form then URI.encode_www_form(body)
    when :json then body.to_json
    else raise ArgumentError, "Unsupported request body format: #{format}"
    end
  end

  # Returns the content type matching the selected request body encoding.
  #
  # @param format [Symbol] :form or :json
  # @return [String] content type
  def body_content_type(format)
    case format
    when :form then "application/x-www-form-urlencoded"
    when :json then "application/json"
    else raise ArgumentError, "Unsupported request body format: #{format}"
    end
  end

  # Rejects incomplete or unusable successful token responses before persistence.
  #
  # @param token_response [Object] parsed token endpoint response
  # @param grant_type [String] OAuth grant type used for this request
  # @return [void]
  # @raise [CodexClient::TokenExchangeError] when required credential fields are absent
  def validate_token_response!(token_response, grant_type)
    required_fields = %w[access_token refresh_token expires_in]
    required_fields << "id_token" if grant_type == "authorization_code"
    valid_response = token_response.is_a?(Hash) && required_fields.all? { |field| token_response[field].present? } && token_response["expires_in"].to_i.positive?
    return if valid_response

    raise TokenExchangeError, "auth.openai.com token endpoint returned an incomplete token response"
  end

  # @return [Hash<String, String>] headers that make a request look like the real Codex CLI
  def cli_impersonation_headers
    {
      "originator" => "codex_cli_rs",
      "User-Agent" => "codex_cli_rs/#{CONFIG.cli_version}",
      "version" => CONFIG.cli_version
    }
  end
end
