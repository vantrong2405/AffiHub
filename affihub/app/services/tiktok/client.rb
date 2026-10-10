class TikTok::Client
  CONFIGURATION = SocialConnections::ProviderConfiguration.for(:tiktok)

  class Error < StandardError
    # Initializes an error that exposes only a safe provider error code.
    #
    # @param code [String] normalized error identifier
    # @return [TikTok::Client::Error] the sanitized API error
    def initialize(code)
      @code = code.to_s
      super(@code)
    end

    # Returns the sanitized provider error identifier.
    #
    # @return [String] a safe error code
    def code
      @code
    end
  end

  # Initializes the TikTok API client with the configured provider values.
  #
  # @param configuration [Hash] TikTok API endpoints, credentials, and limits
  # @return [TikTok::Client] the configured client
  def initialize(configuration: CONFIGURATION)
    @configuration = configuration.deep_symbolize_keys
  end

  # Exchanges one OAuth authorization code for user tokens.
  #
  # @param code [String] the one-time authorization code
  # @param redirect_uri [String] the exact registered callback URI
  # @param code_verifier [String, nil] the PKCE verifier bound to the code
  # @return [Hash] the TikTok token payload
  def exchange_code(code:, redirect_uri:, code_verifier: nil)
    parameters = {
      client_key: @configuration.fetch(:client_id),
      client_secret: @configuration.fetch(:client_secret),
      code:,
      grant_type: "authorization_code",
      redirect_uri:
    }
    parameters[:code_verifier] = code_verifier if code_verifier.present?
    response = request(method: :post, url: @configuration.fetch(:token_url), form_params: parameters)
    step_raise_oauth_error(response)
  end

  # Refreshes an expired or soon-to-expire TikTok user access token.
  #
  # @param refresh_token [String] the encrypted refresh token from the connection
  # @return [Hash] the new TikTok token payload
  def refresh_token(refresh_token:)
    response = request(
      method: :post,
      url: @configuration.fetch(:token_url),
      form_params: {
        client_key: @configuration.fetch(:client_id),
        client_secret: @configuration.fetch(:client_secret),
        grant_type: "refresh_token",
        refresh_token:
      }
    )
    step_raise_oauth_error(response)
  end

  # Loads the TikTok user identity needed to create the connected profile.
  #
  # @param access_token [String] the user access token
  # @return [Hash] the TikTok open ID and display name
  def profile(access_token:)
    response = request(
      method: :get,
      url: api_url(:profile),
      query: { fields: profile_fields },
      headers: authorization_headers(access_token)
    )
    step_raise_api_error(response)
    response.dig("data", "user").to_h.slice("open_id", "display_name")
  end

  # Fetches current privacy, interaction, and duration settings for the creator.
  #
  # @param access_token [String] the creator access token
  # @return [Hash] creator data and provider error details
  def creator_info(access_token:)
    request(
      method: :post,
      url: api_url(:creator_info),
      headers: authorization_headers(access_token).merge("Content-Type" => "application/json; charset=UTF-8")
    )
  end

  # Initializes a TikTok Direct Post using the saved user consent.
  #
  # @param access_token [String] the creator access token
  # @param post_info [Hash] caption, visibility, interaction, and disclosure choices
  # @param source_info [Hash] the FILE_UPLOAD size and chunk metadata
  # @return [Hash] the publish ID, signed upload URL, and provider errors
  def init_video_publish(access_token:, post_info:, source_info:)
    request(
      method: :post,
      url: api_url(:initialize_video_publish),
      headers: authorization_headers(access_token).merge("Content-Type" => "application/json; charset=UTF-8"),
      body: { post_info:, source_info: }.to_json
    )
  end

  # Builds the provider's FILE_UPLOAD metadata for the supplied local file size.
  #
  # @param file_size [Integer] the rendered MP4 size in bytes
  # @return [Hash] TikTok video size, chunk size, and total chunk count
  def file_upload_source_info(file_size:)
    normalized_size = file_size.to_i
    raise Error, client_error_code(:invalid_file_size) unless normalized_size.positive?

    chunk_size = step_chunk_size(normalized_size)
    total_chunk_count = [ normalized_size / chunk_size, 1 ].max
    raise Error, client_error_code(:too_many_upload_chunks) if total_chunk_count > @configuration.fetch(:upload_max_chunks).to_i

    {
      "source" => @configuration.fetch(:upload_source),
      "video_size" => normalized_size,
      "chunk_size" => chunk_size,
      "total_chunk_count" => total_chunk_count
    }
  end

  # Uploads a local render file in sequential chunks and reports confirmed offsets.
  #
  # @param upload_url [String] the signed URL returned by TikTok
  # @param file [IO] an open, seekable local render file
  # @param file_size [Integer] the complete render size in bytes
  # @param resume_offset [Integer] the last offset confirmed by TikTok
  # @yield [uploaded_offset] called after each successful chunk response
  # @yieldparam uploaded_offset [Integer] the next byte to upload
  # @return [Hash] the final uploaded byte offset
  def upload_file(upload_url:, file:, file_size:, resume_offset:)
    validate_upload_url!(upload_url)
    normalized_size = file_size.to_i
    offset = resume_offset.to_i
    raise Error, client_error_code(:invalid_file_size) unless normalized_size.positive?
    raise Error, client_error_code(:invalid_upload_offset) unless offset.between?(0, normalized_size)

    source_info = file_upload_source_info(file_size: normalized_size)
    chunk_size = source_info.fetch("chunk_size")
    total_chunk_count = source_info.fetch("total_chunk_count")
    chunks_sent = offset / chunk_size
    file.seek(offset)

    while offset < normalized_size
      remaining_chunks = total_chunk_count - chunks_sent
      chunk_length = remaining_chunks == 1 ? normalized_size - offset : chunk_size
      validate_final_chunk_size!(chunk_length, remaining_chunks)
      request(
        method: :put,
        url: upload_url,
        headers: {
          "Content-Length" => chunk_length.to_s,
          "Content-Range" => "bytes #{offset}-#{offset + chunk_length - 1}/#{normalized_size}",
          "Content-Type" => @configuration.fetch(:video_content_type)
        },
        stream: file,
        file_size: chunk_length,
        expected_status_code: @configuration.fetch(:upload_response_codes).fetch(remaining_chunks == 1 ? :complete : :partial),
        timeout_seconds: @configuration.fetch(:upload_timeout_seconds)
      )
      offset += chunk_length
      yield(offset) if block_given?
      chunks_sent += 1
    end

    { "uploaded_bytes" => offset }
  end

  # Fetches the current TikTok status for an existing Direct Post.
  #
  # @param access_token [String] the creator access token
  # @param publish_id [String] the saved TikTok publish identifier
  # @return [Hash] current publish status and provider error details
  def publish_status(access_token:, publish_id:)
    request(
      method: :post,
      url: api_url(:publish_status),
      headers: authorization_headers(access_token).merge("Content-Type" => "application/json; charset=UTF-8"),
      body: { publish_id: }.to_json
    )
  end

  # Looks up the provider's share URL for returned public post IDs.
  #
  # @param access_token [String] the creator access token with video.list scope
  # @param video_ids [Array<String>] TikTok public post IDs
  # @return [Hash, nil] matching video fields returned by TikTok
  def video_query(access_token:, video_ids:)
    response = request(
      method: :post,
      url: api_url(:video_query),
      query: { fields: video_query_fields },
      headers: authorization_headers(access_token).merge("Content-Type" => "application/json"),
      body: { filters: { video_ids: video_ids.map(&:to_s) } }.to_json
    )
    step_raise_api_error(response)
    response.dig("data", "videos").to_a.find { |video| video["id"].to_s == video_ids.first.to_s }
  end

  private

  def request(method:, url:, query: {}, form_params: nil, headers: {}, body: nil, stream: nil, file_size: nil,
              expected_status_code: nil, timeout_seconds: nil)
    uri = URI(url)
    merged_query = URI.decode_www_form(uri.query.to_s) + query.to_a
    uri.query = URI.encode_www_form(merged_query) unless merged_query.empty?
    http_request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    headers.each { |name, value| http_request[name] = value }

    if form_params
      http_request["Content-Type"] = "application/x-www-form-urlencoded"
      http_request.body = URI.encode_www_form(form_params)
    elsif body
      http_request.body = body
    end
    http_request.body_stream = stream if stream
    http_request.content_length = file_size if file_size

    timeout = timeout_seconds || @configuration.fetch(:read_timeout_seconds)
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: @configuration.fetch(:open_timeout_seconds),
      read_timeout: timeout
    ) { |http| http.request(http_request) }
    parsed_response = JSON.parse(response.body.presence || "{}")
    raise Error, step_safe_error_code(response, parsed_response) unless response.code.to_i.between?(200, 299)
    raise Error, client_error_code(:upload_not_confirmed) if expected_status_code && response.code.to_i != expected_status_code

    parsed_response
  rescue Error
    raise
  rescue JSON::ParserError
    raise Error, client_error_code(:invalid_json_response)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse
    raise Error, client_error_code(:network_request_failed)
  end

  def api_url(path_key)
    "#{@configuration.fetch(:api_base_url)}#{@configuration.fetch(:api_paths).fetch(path_key)}"
  end

  def profile_fields
    @configuration.fetch(:profile_fields).join(",")
  end

  def video_query_fields
    @configuration.fetch(:video_query_fields).join(",")
  end

  def client_error_code(key)
    @configuration.fetch(:client_error_codes).fetch(key)
  end

  def authorization_headers(access_token)
    { "Authorization" => "Bearer #{access_token}" }
  end

  def step_raise_oauth_error(response)
    return response if response["error"].blank?

    raise Error, step_safe_provider_code(response["error"])
  end

  def step_raise_api_error(response)
    provider_code = response.dig("error", "code")
    return response if provider_code.blank? || provider_code == @configuration.fetch(:successful_response_code)

    raise Error, step_safe_provider_code(provider_code)
  end

  def step_chunk_size(file_size)
    minimum_chunk_size = @configuration.fetch(:upload_min_chunk_size_bytes).to_i
    configured_chunk_size = @configuration.fetch(:upload_chunk_size_bytes).to_i
    return file_size if file_size < minimum_chunk_size
    if file_size > @configuration.fetch(:upload_max_single_chunk_size_bytes).to_i
      return [ configured_chunk_size, file_size / 2 ].min
    end

    [ configured_chunk_size, file_size ].min
  end

  def validate_final_chunk_size!(chunk_length, remaining_chunks)
    return unless remaining_chunks == 1

    maximum_final_chunk = @configuration.fetch(:upload_max_final_chunk_size_bytes).to_i
    raise Error, client_error_code(:upload_chunk_too_large) if chunk_length > maximum_final_chunk
  end

  def validate_upload_url!(upload_url)
    uri = URI(upload_url.to_s)
    allowed_suffix = @configuration.fetch(:upload_host_suffix)
    valid_host = uri.host&.end_with?(allowed_suffix)
    return if uri.is_a?(URI::HTTPS) && valid_host && uri.port == 443 && uri.userinfo.nil?

    raise Error, client_error_code(:invalid_upload_url)
  rescue URI::InvalidURIError
    raise Error, client_error_code(:invalid_upload_url)
  end

  def step_safe_error_code(response, parsed_response)
    provider_error = parsed_response["error"]
    provider_code = provider_error.is_a?(Hash) ? provider_error["code"] : provider_error
    code = step_safe_provider_code(provider_code)
    return code if code.present?

    "#{@configuration.fetch(:http_error_code_prefix)}#{response.code}"
  end

  def step_safe_provider_code(value)
    code = value.to_s
    return if code.blank? || code !~ /\A[a-zA-Z0-9_]+\z/

    code
  end
end
