require "json"
require "net/http"
require "uri"

class Youtube::Client
  class Error < StandardError
    attr_reader :code

    # Initializes a sanitized YouTube API error.
    #
    # @param code [String] safe error category
    # @return [Youtube::Client::Error] the API error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Initializes Google OAuth and YouTube API requests.
  #
  # @return [Youtube::Client] configured client
  def initialize
    @youtube_configuration = Rails.application.config_for(:youtube).deep_symbolize_keys
    @configuration = @youtube_configuration.fetch(:oauth)
  end

  # Exchanges a one-time authorization code using the saved PKCE verifier.
  #
  # @param code [String] authorization code
  # @param redirect_uri [String] exact registered callback URI
  # @param code_verifier [String] session-bound PKCE verifier
  # @return [Hash] token response
  def exchange_code(code:, redirect_uri:, code_verifier:)
    request(
      method: :post,
      url: @configuration.fetch(:token_url),
      form: {
        client_id: @configuration.fetch(:client_id),
        code:,
        code_verifier:,
        grant_type: "authorization_code",
        redirect_uri:
      }
    )
  end

  # Exchanges a Google refresh token for a new access token.
  #
  # @param refresh_token [String] encrypted Google refresh token
  # @return [Hash] refreshed token response
  def refresh_token(refresh_token:)
    request(
      method: :post,
      url: @configuration.fetch(:token_url),
      form: {
        client_id: @configuration.fetch(:client_id),
        grant_type: "refresh_token",
        refresh_token:
      }
    )
  end

  # Reads the stable Google subject for a connected account.
  #
  # @param access_token [String] Google OAuth access token
  # @return [Hash] OIDC subject and display profile
  def profile(access_token:)
    request(
      method: :get,
      url: @configuration.fetch(:userinfo_url),
      headers: { "Authorization" => "Bearer #{access_token}" }
    )
  end

  # Lists channels owned by the authenticated Google user.
  #
  # @param access_token [String] Google OAuth access token with youtube.readonly
  # @return [Array<Hash>] channel IDs and titles available for selection
  def channels(access_token:)
    url = api_url(@configuration.fetch(:channels_endpoint))
    channels = []
    page_token = nil
    pages_read = 0
    loop do
      raise Error, "channel_list_incomplete" if pages_read >= @configuration.fetch(:channel_list_max_pages)

      query = { part: "snippet", mine: true, maxResults: @configuration.fetch(:channel_list_max_results) }
      query[:pageToken] = page_token if page_token
      response = request(
        method: :get,
        url:,
        query:,
        headers: { "Authorization" => "Bearer #{access_token}" }
      )
      pages_read += 1
      channels.concat(response.fetch("items", []).filter_map do |channel|
        next if channel["id"].blank? || channel.dig("snippet", "title").blank?

        { "id" => channel.fetch("id"), "name" => channel.dig("snippet", "title") }
      end)
      page_token = response["nextPageToken"].presence
      break unless page_token
    end
    channels
  end

  # Starts one resumable videos.insert session and returns its signed URI.
  #
  # @param access_token [String] Google OAuth access token with youtube.upload
  # @param metadata [Hash] approved snippet and status fields
  # @param file_size [Integer] total render size in bytes
  # @param content_type [String] render MIME type
  # @return [String] provider session URI to checkpoint before uploading bytes
  def start_resumable_upload(access_token:, metadata:, file_size:, content_type:)
    step_reserve_quota(:videos_insert)
    response = request(
      method: :post,
      url: upload_url,
      query: { uploadType: "resumable", part: "snippet,status" },
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Type" => "application/json; charset=UTF-8",
        "X-Upload-Content-Length" => file_size.to_s,
        "X-Upload-Content-Type" => content_type
      },
      body: metadata.to_json,
      return_response: true
    )
    session_uri = response["Location"]
    raise Error, "missing_upload_session" if session_uri.blank?
    raise Error, "invalid_upload_session" unless valid_upload_session?(session_uri)

    session_uri
  end

  # Reconciles a saved upload session without sending file bytes.
  #
  # @param access_token [String] Google OAuth access token
  # @param session_uri [String] signed provider session URI from the checkpoint
  # @param file_size [Integer] total render size in bytes
  # @return [Hash] confirmed byte offset and video ID when complete
  def upload_status(access_token:, session_uri:, file_size:)
    validate_upload_session!(session_uri)
    response = request(
      method: :put,
      url: session_uri,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Length" => "0",
        "Content-Range" => "bytes */#{file_size}"
      },
      body: "",
      return_response: true,
      accepted_status_codes: upload_response_codes
    )
    upload_result(response, file_size:)
  end

  # Sends only bytes not yet acknowledged by a saved upload session.
  #
  # @param access_token [String] Google OAuth access token
  # @param session_uri [String] signed provider session URI from the checkpoint
  # @param file [IO] open local render file
  # @param file_size [Integer] total render size in bytes
  # @param offset [Integer] first byte not yet acknowledged by YouTube
  # @param content_type [String] render MIME type
  # @return [Hash] confirmed byte offset and video ID when complete
  def upload_remaining(access_token:, session_uri:, file:, file_size:, offset:, content_type:)
    validate_upload_session!(session_uri)
    raise Error, "invalid_upload_offset" unless offset.is_a?(Integer) && offset.between?(0, file_size - 1)

    file.seek(offset)
    response = request(
      method: :put,
      url: session_uri,
      headers: {
        "Authorization" => "Bearer #{access_token}",
        "Content-Length" => (file_size - offset).to_s,
        "Content-Type" => content_type,
        "Content-Range" => "bytes #{offset}-#{file_size - 1}/#{file_size}"
      },
      stream: file,
      return_response: true,
      accepted_status_codes: upload_response_codes,
      timeout_seconds: @configuration.fetch(:upload_timeout_seconds)
    )
    upload_result(response, file_size:)
  end

  # Reads the owner-visible processing and privacy state for an uploaded video.
  #
  # @param access_token [String] Google OAuth access token
  # @param video_id [String] provider video ID returned after upload
  # @return [Hash] exact video resource with processing, status, and channel fields
  def video_status(access_token:, video_id:)
    response = request(
      method: :get,
      url: api_url(@youtube_configuration.fetch(:videos_endpoint)),
      query: { part: "processingDetails,status,snippet", id: video_id },
      headers: { "Authorization" => "Bearer #{access_token}" }
    )
    video = response.fetch("items", []).find { |item| item["id"].to_s == video_id.to_s }
    raise Error, "video_not_found" unless video

    video
  end

  private

  def request(method:, url:, form: nil, query: nil, headers: {}, body: nil, stream: nil, return_response: false,
              accepted_status_codes: [], timeout_seconds: nil)
    uri = URI(url)
    raise Error, "invalid_api_request" unless uri.is_a?(URI::HTTPS)
    uri.query = URI.encode_www_form(query) if query

    http_request = case method
    when :post then Net::HTTP::Post.new(uri)
    when :put then Net::HTTP::Put.new(uri)
    else Net::HTTP::Get.new(uri)
    end
    headers.each { |name, value| http_request[name] = value }
    http_request.set_form_data(form) if form
    http_request.body = body if body
    http_request.body_stream = stream if stream
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: true,
      open_timeout: @configuration.fetch(:open_timeout_seconds),
      read_timeout: timeout_seconds || @configuration.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    payload = JSON.parse(response.body.presence || "{}")
    unless response.is_a?(Net::HTTPSuccess) || accepted_status_codes.include?(response.code.to_i)
      raise Error, safe_error_code(response, payload)
    end

    return response if return_response

    payload
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError, KeyError, ArgumentError
    raise Error, "invalid_api_request"
  end

  def safe_error_code(response, payload)
    error_payload = payload["error"]
    provider_reasons = @youtube_configuration.fetch(:provider_error_reasons)
    return provider_reasons.fetch(:oauth_invalid_grant) if error_payload == provider_reasons.fetch(:oauth_invalid_grant)

    reasons = error_payload.is_a?(Hash) ? error_payload.dig("errors").to_a.filter_map { |error| error["reason"] } : []
    return "quota_exhausted" if reasons.include?(provider_reasons.fetch(:project_quota))
    return "upload_limit_exhausted" if reasons.include?(provider_reasons.fetch(:channel_upload_limit))

    "http_#{response.code}"
  end

  def upload_url
    "#{@youtube_configuration.fetch(:upload_base_url)}/#{@youtube_configuration.fetch(:api_version)}/#{@youtube_configuration.fetch(:videos_endpoint)}"
  end

  def api_url(endpoint)
    "#{@youtube_configuration.fetch(:api_base_url)}/#{@youtube_configuration.fetch(:api_version)}/#{endpoint}"
  end

  def step_reserve_quota(bucket)
    reservation = Youtube::QuotaReservationService.new(bucket:)
    return if reservation.call

    raise Error, "quota_exhausted"
  end

  def upload_response_codes
    @youtube_configuration.fetch(:upload_response_codes).values
  end

  def validate_upload_session!(session_uri)
    raise Error, "invalid_upload_session" unless valid_upload_session?(session_uri)
  end

  def upload_result(response, file_size:)
    codes = @youtube_configuration.fetch(:upload_response_codes)
    if response.code.to_i == codes.fetch(:incomplete)
      range = response["Range"]
      return { uploaded_bytes: 0, video_id: nil } if range.blank?

      match = /\Abytes=0-(\d+)\z/.match(range)
      uploaded_bytes = match[1].to_i + 1 if match
      raise Error, "invalid_upload_range" unless uploaded_bytes&.between?(1, file_size)

      return { uploaded_bytes:, video_id: nil }
    end

    raise Error, "invalid_upload_response" unless response.code.to_i == codes.fetch(:complete)

    video_id = JSON.parse(response.body.presence || "{}")["id"]
    raise Error, "invalid_upload_response" if video_id.blank?

    { uploaded_bytes: file_size, video_id: }
  end

  def valid_upload_session?(value)
    uri = URI(value)
    expected_uri = URI(upload_url)
    uri.is_a?(URI::HTTPS) && uri.host == expected_uri.host && uri.port == expected_uri.port &&
      uri.path == expected_uri.path && uri.userinfo.nil? &&
      URI.decode_www_form(uri.query.to_s).any? do |key, token|
        key == @youtube_configuration.fetch(:upload_session_id_parameter) && token.present?
      end
  rescue URI::InvalidURIError, ArgumentError
    false
  end
end
