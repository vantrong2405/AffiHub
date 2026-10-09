require "net/http"
require "json"

class Google::Client
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys.freeze

  class ApiError < StandardError
    attr_reader :status, :reason

    # Initializes a sanitized Google API error without provider response data.
    #
    # @param status [Integer, nil] the HTTP response status
    # @param reason [String] the safe machine-readable error reason
    # @return [Google::Client::ApiError] the sanitized API error
    def initialize(status:, reason:)
      @status = status
      @reason = reason
      super(reason)
    end
  end

  class DailyQuotaExceeded < ApiError
  end

  class StorageQuotaExceeded < ApiError
  end

  class RateLimitError < ApiError
  end

  class NetworkError < ApiError
  end

  class InvalidGrantError < ApiError
  end

  # Initializes a Google API client for an authorized account.
  #
  # @param access_token [String, nil] the Google OAuth access token
  # @return [Google::Client] the configured client
  def initialize(access_token: nil)
    @access_token = access_token
    @configuration = CONFIGURATION
  end

  # Exchanges a one-time authorization code for OAuth tokens.
  #
  # @param code [String] the authorization code returned by Google
  # @param redirect_uri [String] the registered callback URI
  # @param code_verifier [String, nil] the PKCE verifier for this attempt
  # @return [Hash] the token response
  def exchange_code(code:, redirect_uri:, code_verifier: nil)
    form = {
      client_id: @configuration.dig(:oauth, :client_id),
      client_secret: @configuration.dig(:oauth, :client_secret),
      code:,
      code_verifier:,
      grant_type: "authorization_code",
      redirect_uri:
    }.compact

    request(method: :post, url: @configuration.dig(:oauth, :token_url), form:)
  end

  # Refreshes an expired access token without requesting additional scopes.
  #
  # @param refresh_token [String] the encrypted refresh token
  # @return [Hash] the refreshed access token response
  def refresh_access_token(refresh_token:)
    form = {
      client_id: @configuration.dig(:oauth, :client_id),
      client_secret: @configuration.dig(:oauth, :client_secret),
      grant_type: "refresh_token",
      refresh_token:
    }

    request(method: :post, url: @configuration.dig(:oauth, :token_url), form:)
  end

  # Loads the Google account identity authorized by the access token.
  #
  # @param access_token [String] the OAuth access token
  # @return [Hash] the Google subject and email
  def profile(access_token: @access_token)
    request(
      method: :get,
      url: @configuration.dig(:oauth, :profile_url),
      headers: { "Authorization" => "Bearer #{access_token}" }
    )
  end

  # Finds a private project folder using its stable Drive app property.
  #
  # @param folder_key [String] the project-scoped idempotency key
  # @return [Hash, nil] the matching Drive folder metadata
  def find_folder(folder_key:)
    find_file_by_property(
      property_key: @configuration.dig(:drive, :folder_app_property_key),
      property_value: folder_key,
      mime_type: @configuration.dig(:drive, :folder_mime_type)
    )
  end

  # Creates a private Drive folder that inherits its parent permissions.
  #
  # @param folder_key [String] the project-scoped idempotency key
  # @param name [String] the Vietnamese project folder name
  # @param parent_id [String, nil] the selected parent folder ID
  # @return [Hash] the created Drive folder metadata
  def create_folder(folder_key:, name:, parent_id:)
    metadata = {
      name:,
      mimeType: @configuration.dig(:drive, :folder_mime_type),
      appProperties: { @configuration.dig(:drive, :folder_app_property_key) => folder_key }
    }
    metadata[:parents] = [ parent_id ] if parent_id.present?

    request(
      method: :post,
      url: "#{@configuration.dig(:drive, :api_base_url)}/files",
      params: { fields: @configuration.dig(:drive, :fields) },
      headers: {
        "Authorization" => authorization_header,
        "Content-Type" => "application/json"
      },
      body: metadata
    )
  end

  # Finds a private render file using its stable export app property.
  #
  # @param file_key [String] the render/export-scoped idempotency key
  # @return [Hash, nil] the matching Drive file metadata
  def find_file(file_key:)
    find_file_by_property(
      property_key: @configuration.dig(:drive, :file_app_property_key),
      property_value: file_key
    )
  end

  # Lists Drive folders visible under the connection's granted file scope.
  #
  # @return [Array<Hash>] the accessible Drive folder metadata
  def list_drive_folders
    drive_configuration = @configuration.fetch(:drive)
    response = request(
      method: :get,
      url: "#{drive_configuration.fetch(:api_base_url)}/files",
      params: {
        fields: "files(#{drive_configuration.fetch(:folder_fields)})",
        pageSize: drive_configuration.fetch(:folder_page_size),
        q: "mimeType = '#{drive_configuration.fetch(:folder_mime_type)}' and trashed = false"
      },
      headers: { "Authorization" => authorization_header }
    )
    response.fetch("files", [])
  end

  # Loads one Drive folder so the settings form can validate its parent selection.
  #
  # @param folder_id [String] the selected parent folder ID
  # @return [Hash] the accessible folder metadata
  def find_drive_folder(folder_id:)
    drive_configuration = @configuration.fetch(:drive)
    encoded_folder_id = URI.encode_www_form_component(folder_id.to_s)
    request(
      method: :get,
      url: "#{drive_configuration.fetch(:api_base_url)}/files/#{encoded_folder_id}",
      params: { fields: drive_configuration.fetch(:folder_fields) },
      headers: { "Authorization" => authorization_header }
    )
  end

  # Returns worksheet tabs available in one user-selected Google spreadsheet.
  #
  # @param spreadsheet_id [String] the spreadsheet selected by the user
  # @return [Array<Hash>] the worksheet IDs, titles, and order
  def spreadsheet_worksheets(spreadsheet_id:)
    sheets_configuration = @configuration.fetch(:sheets)
    encoded_spreadsheet_id = URI.encode_www_form_component(spreadsheet_id.to_s)
    response = request(
      method: :get,
      url: "#{sheets_configuration.fetch(:api_base_url)}/spreadsheets/#{encoded_spreadsheet_id}",
      params: { fields: sheets_configuration.fetch(:spreadsheet_fields) },
      headers: { "Authorization" => authorization_header }
    )
    response.fetch("sheets", []).filter_map do |sheet|
      sheet.fetch("properties", nil)
    end
  end

  # Starts a Google Drive resumable upload session for one render file.
  #
  # @param folder_id [String] the private project folder ID
  # @param file_key [String] the render/export-scoped idempotency key
  # @param file_name [String] the render filename shown in Drive
  # @param file_size [Integer] the render size in bytes
  # @return [String] the validated resumable session URI
  def create_upload_session(folder_id:, file_key:, file_name:, file_size:)
    metadata = {
      name: file_name,
      mimeType: @configuration.dig(:drive, :file_mime_type),
      parents: [ folder_id ],
      appProperties: { @configuration.dig(:drive, :file_app_property_key) => file_key }
    }
    response = request(
      method: :post,
      url: "#{@configuration.dig(:drive, :upload_base_url)}/files",
      params: { fields: @configuration.dig(:drive, :fields), uploadType: "resumable" },
      headers: {
        "Authorization" => authorization_header,
        "Content-Type" => "application/json; charset=UTF-8",
        "X-Upload-Content-Length" => file_size.to_s,
        "X-Upload-Content-Type" => @configuration.dig(:drive, :upload_content_type)
      },
      body: metadata,
      return_response: true
    )
    session_uri = response["Location"]
    validate_upload_session_uri!(session_uri)
    session_uri
  end

  # Uploads render bytes through a resumable session and resumes interrupted transfers.
  #
  # @param session_uri [String] the encrypted Google resumable session URI
  # @param file [IO] the open local render file
  # @param file_size [Integer] the complete render size in bytes
  # @return [Hash] the completed Drive file metadata
  def upload_file(session_uri:, file:, file_size:)
    validate_upload_session_uri!(session_uri)
    file.rewind
    response = request(
      method: :put,
      url: session_uri,
      headers: { "Content-Type" => @configuration.dig(:drive, :upload_content_type) },
      stream: file,
      file_size:,
      timeout_seconds: @configuration.dig(:requests, :upload_timeout_seconds),
      return_response: true,
      accepted_status_codes: [ 308 ]
    )
    return step_parse_upload_response(response) if response.is_a?(Net::HTTPSuccess)

    step_resume_upload(session_uri:, file:, file_size:)
  rescue NetworkError
    step_resume_upload(session_uri:, file:, file_size:)
  end

  # Updates the existing keyed Sheet row or appends one RAW row when the key is absent.
  #
  # @param spreadsheet_id [String] the spreadsheet selected by the user
  # @param worksheet_title [String] the worksheet selected by the user
  # @param row_key [String] the stable project/render/destination key in column A
  # @param values [Array<String>] the current row values in configured column order
  # @return [Integer] the one-based row number confirmed by Google Sheets
  def upsert_sheet_row(spreadsheet_id:, worksheet_title:, row_key:, values:)
    row_number = step_find_sheet_row(spreadsheet_id:, worksheet_title:, row_key:)
    return step_update_sheet_row(spreadsheet_id:, worksheet_title:, row_number:, values:) if row_number

    step_append_sheet_row(spreadsheet_id:, worksheet_title:, values:)
  end

  private

  def find_file_by_property(property_key:, property_value:, mime_type: nil)
    predicates = [
      "trashed = false",
      "appProperties has { key='#{escape_query_value(property_key)}' and value='#{escape_query_value(property_value)}' }"
    ]
    predicates << "mimeType = '#{escape_query_value(mime_type)}'" if mime_type

    response = request(
      method: :get,
      url: "#{@configuration.dig(:drive, :api_base_url)}/files",
      params: {
        fields: "files(#{@configuration.dig(:drive, :fields)})",
        pageSize: @configuration.dig(:drive, :page_size),
        q: predicates.join(" and "),
        spaces: "drive"
      },
      headers: { "Authorization" => authorization_header }
    )
    response.fetch("files", []).first
  end

  def validate_upload_session_uri!(session_uri)
    uri = URI(session_uri.to_s)
    allowed_hosts = @configuration.dig(:drive, :allowed_upload_hosts)
    valid_uri = uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? && allowed_hosts.include?(uri.host)
    return if valid_uri

    raise ApiError.new(status: nil, reason: @configuration.dig(:client_errors, :invalid_upload_session_uri))
  rescue URI::InvalidURIError
    raise ApiError.new(status: nil, reason: @configuration.dig(:client_errors, :invalid_upload_session_uri))
  end

  def request(method:, url:, params: {}, headers: {}, form: nil, body: nil, stream: nil, file_size: nil,
              timeout_seconds: nil, return_response: false, accepted_status_codes: [])
    uri = URI(url)
    query = URI.decode_www_form(uri.query.to_s) + params.to_a
    uri.query = URI.encode_www_form(query) unless query.empty?
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri)
    headers.each { |name, value| http_request[name] = value }
    http_request.set_form_data(form) if form
    http_request.body = body.is_a?(String) ? body : JSON.generate(body) if body
    http_request.body_stream = stream if stream
    http_request.content_length = file_size if file_size
    timeout = timeout_seconds || @configuration.dig(:requests, :read_timeout_seconds)
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: @configuration.dig(:requests, :open_timeout_seconds),
      read_timeout: timeout
    ) { |http| http.request(http_request) }
    return response if return_response && (
      response.is_a?(Net::HTTPSuccess) || accepted_status_codes.include?(response.code.to_i)
    )

    payload = JSON.parse(response.body.presence || "{}")
    successful_response = response.is_a?(Net::HTTPSuccess) || accepted_status_codes.include?(response.code.to_i)
    raise_api_error(response, payload) unless successful_response

    payload
  rescue JSON::ParserError
    raise ApiError.new(status: nil, reason: @configuration.dig(:client_errors, :invalid_json_response))
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError, Timeout::Error
    raise NetworkError.new(status: nil, reason: @configuration.dig(:client_errors, :network_request_failed))
  rescue URI::InvalidURIError, KeyError, ArgumentError
    raise ApiError.new(status: nil, reason: @configuration.dig(:client_errors, :invalid_api_request))
  end

  def raise_api_error(response, payload)
    status = response.code.to_i
    error_payload = payload["error"]
    errors = error_payload.is_a?(Hash) ? error_payload.fetch("errors", []).to_a : []
    reasons = errors.filter_map { |error| error["reason"] }
    api_errors = @configuration.fetch(:api_errors)
    oauth_errors = @configuration.fetch(:oauth_errors)
    oauth_error = error_payload if error_payload.is_a?(String)

    error_class, reason = if oauth_error == oauth_errors.fetch(:invalid_grant)
      [ InvalidGrantError, oauth_errors.fetch(:invalid_grant) ]
    elsif (reasons & [ api_errors.fetch(:daily_quota), api_errors.fetch(:quota_exhausted) ]).any?
      [ DailyQuotaExceeded, (reasons & [ api_errors.fetch(:daily_quota), api_errors.fetch(:quota_exhausted) ]).first ]
    elsif reasons.include?(api_errors.fetch(:storage_quota))
      [ StorageQuotaExceeded, api_errors.fetch(:storage_quota) ]
    elsif status == 429 || (reasons & api_errors.fetch(:rate_limits)).any?
      [ RateLimitError, (reasons & api_errors.fetch(:rate_limits)).first || api_errors.fetch(:rate_limits).first ]
    else
      [ ApiError, "#{@configuration.dig(:client_errors, :http_error_prefix)}#{status}" ]
    end

    raise error_class.new(status:, reason:)
  end

  def authorization_header
    "Bearer #{@access_token}"
  end

  def escape_query_value(value)
    value.to_s.gsub("\\", "\\\\").gsub("'", "\\'")
  end

  def step_resume_upload(session_uri:, file:, file_size:)
    attempts = 0

    loop do
      status_response = request(
        method: :put,
        url: session_uri,
        headers: {
          "Content-Length" => "0",
          "Content-Range" => "bytes */#{file_size}"
        },
        body: "",
        timeout_seconds: @configuration.dig(:requests, :upload_timeout_seconds),
        return_response: true,
        accepted_status_codes: [ 308 ]
      )
      return step_parse_upload_response(status_response) if status_response.is_a?(Net::HTTPSuccess)

      offset = step_upload_offset(status_response["Range"])
      raise NetworkError.new(
        status: 308,
        reason: @configuration.dig(:client_errors, :upload_session_not_complete)
      ) if offset >= file_size

      file.seek(offset)
      remaining_bytes = file_size - offset
      upload_response = request(
        method: :put,
        url: session_uri,
        headers: {
          "Content-Range" => "bytes #{offset}-#{file_size - 1}/#{file_size}",
          "Content-Type" => @configuration.dig(:drive, :upload_content_type)
        },
        stream: file,
        file_size: remaining_bytes,
        timeout_seconds: @configuration.dig(:requests, :upload_timeout_seconds),
        return_response: true,
        accepted_status_codes: [ 308 ]
      )
      return step_parse_upload_response(upload_response) if upload_response.is_a?(Net::HTTPSuccess)

      attempts += 1
      raise NetworkError.new(
        status: 308,
        reason: @configuration.dig(:client_errors, :upload_resume_limit_reached)
      ) if
        attempts >= @configuration.dig(:drive, :max_upload_resume_attempts)
    rescue NetworkError
      attempts += 1
      raise if attempts >= @configuration.dig(:drive, :max_upload_resume_attempts)
    end
  end

  def step_parse_upload_response(response)
    JSON.parse(response.body.presence || "{}")
  rescue JSON::ParserError
    raise ApiError.new(
      status: response.code.to_i,
      reason: @configuration.dig(:client_errors, :invalid_json_response)
    )
  end

  def step_upload_offset(range_header)
    return 0 if range_header.blank?

    match = range_header.match(/\Abytes[ =]0-(\d+)\z/)
    raise ApiError.new(status: 308, reason: @configuration.dig(:client_errors, :invalid_upload_range)) unless match

    match[1].to_i + 1
  end

  def step_find_sheet_row(spreadsheet_id:, worksheet_title:, row_key:)
    configuration = @configuration.fetch(:sheets)
    range = step_sheet_range(worksheet_title:, columns: configuration.fetch(:row_lookup_column))
    response = request(
      method: :get,
      url: step_sheet_values_url(spreadsheet_id:, range:),
      params: { majorDimension: "ROWS" },
      headers: { "Authorization" => authorization_header }
    )
    row_index = response.fetch("values", []).index { |row| row.first == row_key }
    row_index ? row_index + 1 : nil
  end

  def step_append_sheet_row(spreadsheet_id:, worksheet_title:, values:)
    configuration = @configuration.fetch(:sheets)
    columns = "#{configuration.fetch(:row_first_column)}:#{configuration.fetch(:row_last_column)}"
    range = step_sheet_range(worksheet_title:, columns:)
    response = request(
      method: :post,
      url: "#{step_sheet_values_url(spreadsheet_id:, range:)}:append",
      params: {
        valueInputOption: configuration.fetch(:row_value_input_option),
        insertDataOption: configuration.fetch(:row_insert_data_option)
      },
      headers: {
        "Authorization" => authorization_header,
        "Content-Type" => "application/json"
      },
      body: { values: [ values ] }
    )
    step_sheet_response_row_number(response.dig("updates", "updatedRange"))
  end

  def step_update_sheet_row(spreadsheet_id:, worksheet_title:, row_number:, values:)
    configuration = @configuration.fetch(:sheets)
    columns = "#{configuration.fetch(:row_first_column)}#{row_number}:#{configuration.fetch(:row_last_column)}#{row_number}"
    range = step_sheet_range(worksheet_title:, columns:)
    response = request(
      method: :put,
      url: step_sheet_values_url(spreadsheet_id:, range:),
      params: { valueInputOption: configuration.fetch(:row_value_input_option) },
      headers: {
        "Authorization" => authorization_header,
        "Content-Type" => "application/json"
      },
      body: { values: [ values ] }
    )
    step_sheet_response_row_number(response.fetch("updatedRange", nil)) || row_number
  end

  def step_sheet_range(worksheet_title:, columns:)
    escaped_title = worksheet_title.to_s.gsub("'", "''")
    "'#{escaped_title}'!#{columns}"
  end

  def step_sheet_values_url(spreadsheet_id:, range:)
    encoded_spreadsheet_id = URI.encode_www_form_component(spreadsheet_id.to_s)
    encoded_range = URI.encode_www_form_component(range)
    "#{@configuration.dig(:sheets, :api_base_url)}/spreadsheets/#{encoded_spreadsheet_id}/values/#{encoded_range}"
  end

  def step_sheet_response_row_number(updated_range)
    return nil if updated_range.blank?

    match = updated_range.match(/![A-Z]+(\d+):[A-Z]+\d+\z/)
    match ? match[1].to_i : nil
  end
end
