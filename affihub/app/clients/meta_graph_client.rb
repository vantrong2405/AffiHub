# frozen_string_literal: true

require "net/http"
require "json"

# Official Meta Graph API client. All endpoints and transport timeouts are config-driven.
class MetaGraphClient
  CONFIG = Rails.application.config_for(:facebook)

  class ApiError < StandardError
    attr_reader :code, :trace_id

    # @param message [String] provider error description
    # @param code [String, Integer, nil] provider error code when supplied
    # @param trace_id [String, nil] provider trace identifier when supplied
    # @return [void]
    def initialize(message, code: nil, trace_id: nil)
      @code = code
      @trace_id = trace_id
      super(message)
    end
  end

  class TransportError < StandardError; end

  # Builds the Meta OAuth authorization URL.
  #
  # @param state [String] one-time CSRF token stored in the Rails session
  # @param redirect_uri [String] registered callback URL
  # @return [String] authorization URL
  def build_authorize_url(state:, redirect_uri:)
    uri = URI.join(CONFIG.authorize_url, CONFIG.authorize_path)
    uri.query = URI.encode_www_form(
      client_id: app_id,
      redirect_uri:,
      scope: CONFIG.permissions.join(","),
      response_type: "code",
      state:
    )
    uri.to_s
  end

  # Exchanges a Meta authorization code for a short-lived user token.
  #
  # @param code [String] authorization code from Meta callback
  # @param redirect_uri [String] callback URL used in the authorize request
  # @return [Hash] token response
  def exchange_token(code:, redirect_uri:)
    request_json(CONFIG.token_url, method: :post, params: {
      client_id: app_id,
      client_secret: app_secret,
      redirect_uri:,
      code:
    })
  end

  # Exchanges a short-lived token for a long-lived user token.
  #
  # @param access_token [String] short-lived user access token
  # @return [Hash] long-lived token response
  def exchange_long_lived_token(access_token:)
    request_json(CONFIG.token_url, method: :get, params: {
      grant_type: "fb_exchange_token",
      client_id: app_id,
      client_secret: app_secret,
      fb_exchange_token: access_token
    })
  end

  # Returns the Facebook Pages visible to the connected user.
  #
  # @param access_token [String] long-lived user token
  # @return [Array<Hash>] Page records with id, name, and picture metadata
  def list_pages(access_token:)
    response = request_json(graph_endpoint(CONFIG.pages_path), method: :get, params: {
      fields: CONFIG.pages_fields,
      access_token:
    })
    response.fetch("data", [])
  end

  # Fetches a fresh Page access token for one selected Page.
  #
  # @param page_id [String] Page id already verified against recent discovery
  # @param access_token [String] long-lived user token
  # @return [String] Page access token
  def fetch_page_token(page_id:, access_token:)
    path = format(CONFIG.page_token_path, page_id: page_id)
    response = request_json(graph_endpoint(path), method: :get, params: { fields: CONFIG.page_token_fields, access_token: })
    response.fetch("access_token")
  rescue KeyError
    raise ApiError, "Meta returned no Page access token"
  end

  # Publishes a text post to a Facebook Page feed.
  #
  # @param page_id [String] destination Page id
  # @param page_access_token [String] encrypted Page token decrypted by the model
  # @param message [String] complete post body
  # @return [Hash] provider response containing post id
  def publish_post(page_id:, page_access_token:, message:)
    path = format(CONFIG.page_feed_path, page_id: page_id)
    request_json(graph_endpoint(path), method: :post, params: {
      message:,
      access_token: page_access_token
    })
  end

  # Fetches the canonical URL for a successfully created Page post.
  #
  # @param post_id [String] id returned by Meta after publish
  # @param page_access_token [String] Page access token
  # @return [String, nil] permalink URL when Meta returns it
  def fetch_permalink_url(post_id:, page_access_token:)
    path = format(CONFIG.permalink_path, post_id: post_id)
    request_json(graph_endpoint(path), method: :get, params: {
      fields: CONFIG.permalink_fields,
      access_token: page_access_token
    }).fetch("permalink_url", nil)
  end

  private

  # Returns the configured app id without exposing a fallback in production.
  #
  # @return [String] Meta developer app id
  # @raise [KeyError] when app credentials are not configured
  def app_id
    value = CONFIG[:app_id].presence || Rails.application.credentials.dig(:facebook, :app_id)
    raise KeyError, "Facebook app_id is not configured" if value.blank?

    value
  end

  # Returns the configured app secret without exposing it to callers.
  #
  # @return [String] Meta developer app secret
  # @raise [KeyError] when app credentials are not configured
  def app_secret
    value = CONFIG[:app_secret].presence || Rails.application.credentials.dig(:facebook, :app_secret)
    raise KeyError, "Facebook app_secret is not configured" if value.blank?

    value
  end

  # Builds a versioned Graph API resource URL from configured hosts and version.
  #
  # @param path [String] Graph node or edge path
  # @return [String] absolute versioned Graph API URL
  def graph_endpoint(path)
    URI.join(CONFIG.graph_url, "/#{CONFIG.api_version}/#{path}").to_s
  end

  # Sends one configured GET or POST request and parses its JSON response.
  #
  # @param url [String] absolute request URL
  # @param method [Symbol] supported HTTP method
  # @param params [Hash] URL-encoded request parameters
  # @return [Hash] parsed JSON response
  # @raise [MetaGraphClient::ApiError] for provider errors or invalid responses
  # @raise [MetaGraphClient::TransportError] for network failures
  def request_json(url, method:, params:)
    uri = URI(url)
    request = if method == :get
      uri.query = URI.encode_www_form(params)
      Net::HTTP::Get.new(uri)
    elsif method == :post
      post = Net::HTTP::Post.new(uri)
      post.set_form_data(params)
      post
    else
      raise ArgumentError, "Unsupported Meta Graph HTTP method: #{method}"
    end
    request["Accept"] = "application/json"

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIG.open_timeout,
      read_timeout: CONFIG.read_timeout,
      write_timeout: CONFIG.write_timeout
    ) { |http| http.request(request) }
    payload = JSON.parse(response.body)
    raise_api_error(payload, response.code) unless response.is_a?(Net::HTTPSuccess)

    payload
  rescue JSON::ParserError
    raise ApiError, "Meta returned invalid JSON"
  rescue Timeout::Error, SocketError, SystemCallError, EOFError, IOError, OpenSSL::SSL::SSLError => error
    raise TransportError, error.class.name
  end

  # Converts a Meta error envelope into a provider error without token data.
  #
  # @param payload [Hash] parsed provider response
  # @param status [String] HTTP response status
  # @return [void]
  # @raise [MetaGraphClient::ApiError] parsed error
  def raise_api_error(payload, status)
    error = payload.fetch("error", {})
    message = error["message"].presence || "Meta Graph API returned #{status}"
    raise ApiError.new(message, code: error["code"], trace_id: error["fbtrace_id"])
  end
end
