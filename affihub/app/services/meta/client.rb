class Meta::Client
  class Error < StandardError
    attr_reader :code

    # Initializes an API error that contains no provider response or credential.
    #
    # @param code [String] a safe error category
    # @return [Meta::Client::Error] the sanitized API error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Initializes Graph API requests with one configured Meta provider.
  #
  # @param provider [String, Symbol] the Facebook or Instagram connection provider
  # @return [Meta::Client] the configured Graph API client
  def initialize(provider: :facebook)
    @configuration = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers).fetch(provider.to_sym)
  end

  # Exchanges the authorization code for a Facebook user access token.
  #
  # @param code [String] the single-use authorization code
  # @param redirect_uri [String] the registered callback URL
  # @param code_verifier [String, nil] PKCE verifier when enabled for this provider
  # @return [Hash] the token response
  def exchange_code(code:, redirect_uri:, code_verifier: nil)
    params = {
      client_id: @configuration.fetch(:client_id),
      client_secret: @configuration.fetch(:client_secret),
      redirect_uri:,
      code:
    }
    params[:code_verifier] = code_verifier if code_verifier.present?
    request(method: :get, url: "#{graph_api_base_url}/oauth/access_token", params:)
  end

  # Loads the connected Facebook profile.
  #
  # @param access_token [String] the user access token
  # @return [Hash] the profile ID and display name
  def profile(access_token:)
    request(method: :get, url: "#{graph_api_base_url}/me", params: { fields: "id,name", access_token: })
  end

  # Lists Facebook Pages available to the connected profile.
  #
  # @param access_token [String] the user access token
  # @return [Array<Hash>] available Pages and their Page access tokens
  def pages(access_token:)
    response = request(
      method: :get,
      url: "#{graph_api_base_url}/me/accounts",
      params: { fields: @configuration.fetch(:page_fields).join(","), access_token: }
    )
    response.fetch("data", [])
  end

  # Reads the current Instagram content publishing quota for a Business account.
  #
  # @param instagram_user_id [String] the selected Instagram Business account ID
  # @param page_access_token [String] the token authorized for the linked Page
  # @return [Hash] the current quota usage and provider-reported quota configuration
  def instagram_content_publishing_limit(instagram_user_id:, page_access_token:)
    encoded_user_id = URI.encode_www_form_component(instagram_user_id)
    request(
      method: :get,
      url: "#{graph_api_base_url}/#{encoded_user_id}/content_publishing_limit",
      params: {
        fields: @configuration.fetch(:instagram_content_publishing_limit_fields).join(","),
        access_token: page_access_token
      }
    )
  end

  # Creates a resumable Instagram Reel container for local binary upload.
  #
  # @param instagram_user_id [String] the selected Instagram Business account ID
  # @param page_access_token [String] the token authorized for the linked Page
  # @param caption [String] the approved caption for this Publication
  # @return [Hash] the container ID and signed binary upload URI
  def start_instagram_reel_upload(instagram_user_id:, page_access_token:, caption:)
    encoded_user_id = URI.encode_www_form_component(instagram_user_id)
    request(
      method: :post,
      url: "#{graph_api_base_url}/#{encoded_user_id}/media",
      params: {
        media_type: @configuration.fetch(:instagram_media_type),
        upload_type: @configuration.fetch(:instagram_upload_type),
        caption:,
        access_token: page_access_token
      }
    )
  end

  # Uploads a local render file to Instagram's signed resumable upload URI.
  #
  # @param upload_url [String] the signed URI returned by Instagram
  # @param page_access_token [String] the token authorized for the linked Page
  # @param file [IO] the open local render file
  # @param file_size [Integer] the complete render size in bytes
  # @return [Hash] the provider upload acknowledgement
  def upload_instagram_reel(upload_url:, page_access_token:, file:, file_size:)
    upload_reel(upload_url:, page_access_token:, file:, file_size:)
  end

  # Reads upload processing status for an existing Instagram media container.
  #
  # @param creation_id [String] the saved media container ID
  # @param page_access_token [String] the token authorized for the linked Page
  # @return [Hash] the container status returned by Instagram
  def instagram_reel_status(creation_id:, page_access_token:)
    encoded_creation_id = URI.encode_www_form_component(creation_id)
    request(
      method: :get,
      url: "#{graph_api_base_url}/#{encoded_creation_id}",
      params: {
        fields: @configuration.fetch(:instagram_container_status_fields).join(","),
        access_token: page_access_token
      }
    )
  end

  # Publishes a finished Instagram Reels container.
  #
  # @param instagram_user_id [String] the selected Instagram Business account ID
  # @param page_access_token [String] the token authorized for the linked Page
  # @param creation_id [String] the finished container ID
  # @return [Hash] the media ID returned by Instagram after publish
  def publish_instagram_reel(instagram_user_id:, page_access_token:, creation_id:)
    encoded_user_id = URI.encode_www_form_component(instagram_user_id)
    request(
      method: :post,
      url: "#{graph_api_base_url}/#{encoded_user_id}/media_publish",
      params: { creation_id:, access_token: page_access_token }
    )
  end

  # Reads the published media ID and permalink returned by Instagram.
  #
  # @param media_id [String] the media ID returned by `media_publish`
  # @param page_access_token [String] the token authorized for the linked Page
  # @return [Hash] the media fields returned by Instagram
  def instagram_media(media_id:, page_access_token:)
    encoded_media_id = URI.encode_www_form_component(media_id)
    request(
      method: :get,
      url: "#{graph_api_base_url}/#{encoded_media_id}",
      params: {
        fields: @configuration.fetch(:instagram_media_fields).join(","),
        access_token: page_access_token
      }
    )
  end

  # Reads a Page-owned Video node without logging its potentially signed source URL.
  #
  # @param video_id [String] the Meta Video ID
  # @param page_access_token [String] the token authorized for the owning Page
  # @return [Hash] the Video ID and source URL when the current app permissions allow them
  def page_video(video_id:, page_access_token:)
    encoded_video_id = URI.encode_www_form_component(video_id)
    request(
      method: :get,
      url: "#{graph_api_base_url}/#{encoded_video_id}",
      params: { fields: "id,source", access_token: page_access_token }
    )
  end

  # Starts a Facebook Reels upload session.
  #
  # @param page_id [String] the selected Facebook Page ID
  # @param page_access_token [String] the selected Page access token
  # @return [Hash] the remote video ID and upload URL
  def start_reel_upload(page_id:, page_access_token:)
    encoded_page_id = URI.encode_www_form_component(page_id)
    request(
      method: :post,
      url: "#{graph_api_base_url}/#{encoded_page_id}/video_reels",
      params: { upload_phase: "start", access_token: page_access_token }
    )
  end

  # Uploads a local MP4 file to a Facebook Reels upload session.
  #
  # @param upload_url [String] the upload URL returned by Meta
  # @param page_access_token [String] the selected Page access token
  # @param file [IO] the open local render file
  # @param file_size [Integer] the file size in bytes
  # @return [Hash] the remote upload acknowledgement
  def upload_reel(upload_url:, page_access_token:, file:, file_size:)
    validate_upload_url!(upload_url)
    file.rewind
    request(
      method: :post,
      url: upload_url,
      headers: {
        "Authorization" => "OAuth #{page_access_token}",
        "offset" => "0",
        "file_size" => file_size.to_s,
        "Content-Type" => "application/octet-stream"
      },
      stream: file,
      file_size:,
      timeout_seconds: @configuration.fetch(:upload_timeout_seconds)
    )
  end

  # Finishes and publishes an uploaded Reel.
  #
  # @param page_id [String] the selected Facebook Page ID
  # @param page_access_token [String] the selected Page access token
  # @param video_id [String] the upload session's video ID
  # @param caption [String] the Reel description
  # @return [Hash] the provider acknowledgement for the publish request
  def finish_reel_upload(page_id:, page_access_token:, video_id:, caption:)
    encoded_page_id = URI.encode_www_form_component(page_id)
    request(
      method: :post,
      url: "#{graph_api_base_url}/#{encoded_page_id}/video_reels",
      params: {
        upload_phase: "finish",
        video_id:,
        video_state: "PUBLISHED",
        description: caption,
        access_token: page_access_token
      }
    )
  end

  # Reads processing and publication status for a Reel.
  #
  # @param video_id [String] the remote Reel video ID
  # @param page_access_token [String] the selected Page access token
  # @return [Hash] the provider status and permalink when available
  def reel_status(video_id:, page_access_token:)
    encoded_video_id = URI.encode_www_form_component(video_id)
    request(
      method: :get,
      url: "#{graph_api_base_url}/#{encoded_video_id}",
      params: { fields: "status,permalink_url", access_token: page_access_token }
    )
  end

  private

  def validate_upload_url!(upload_url)
    uri = URI(upload_url.to_s)
    return if uri.is_a?(URI::HTTPS) && uri.host == "rupload.facebook.com" && uri.port == 443 && uri.userinfo.nil?

    raise Error, "invalid_upload_url"
  rescue URI::InvalidURIError
    raise Error, "invalid_upload_url"
  end

  def request(method:, url:, params: {}, headers: {}, stream: nil, file_size: nil, timeout_seconds: nil)
    uri = URI(url)
    query = URI.decode_www_form(uri.query.to_s) + params.to_a
    uri.query = URI.encode_www_form(query) unless query.empty?
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri)
    headers.each { |name, value| http_request[name] = value }
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
    raise Error, safe_error_code(response, parsed_response) unless response.is_a?(Net::HTTPSuccess)
    raise Error, safe_error_code(response, parsed_response) if parsed_response.key?("error")

    parsed_response
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  end

  def graph_api_base_url
    "#{@configuration.fetch(:graph_api_base_url)}/#{@configuration.fetch(:api_version)}"
  end

  def safe_error_code(response, parsed_response)
    provider_code = parsed_response.dig("error", "code")
    return "graph_api_#{provider_code}" if provider_code.present?

    "graph_api_http_#{response.code}"
  end
end
