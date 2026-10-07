# frozen_string_literal: true

class Mpt::Client
  CONFIGURATION = Rails.application.config_for(:money_printer_turbo).deep_symbolize_keys

  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe error category
    # @return [Mpt::Client::Error] the sanitized provider error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Creates a draft script through the pinned MoneyPrinterTurbo API.
  #
  # @param video_subject [String] the video topic
  # @param video_language [String] the requested script language
  # @param paragraph_number [Integer] the number of script paragraphs
  # @param video_script_prompt [String] the script and tone instructions
  # @param custom_system_prompt [String] optional system-level instructions
  # @return [Hash] the generated script response
  def generate_script(video_subject:, video_language:, paragraph_number:, video_script_prompt:, custom_system_prompt:)
    request(
      method: :post,
      endpoint: CONFIGURATION.dig(:endpoints, :scripts),
      payload: {
        video_subject:,
        video_language:,
        paragraph_number:,
        video_script_prompt:,
        custom_system_prompt:
      }
    )
  end

  # Creates scene material terms from an approved video script.
  #
  # @param video_subject [String] the video topic
  # @param video_script [String] the approved script
  # @param amount [Integer] the requested scene count
  # @param match_materials_to_script [Boolean] whether terms follow script order
  # @return [Hash] the generated video terms response
  def generate_terms(video_subject:, video_script:, amount:, match_materials_to_script:)
    request(
      method: :post,
      endpoint: CONFIGURATION.dig(:endpoints, :terms),
      payload: { video_subject:, video_script:, amount:, match_materials_to_script: }
    )
  end

  # Submits one approved video generation request to MoneyPrinterTurbo.
  #
  # @param payload [Hash] the validated MPT video request
  # @param task_id [String] the stable correlation ID for submission recovery
  # @return [Hash] the provider response containing the task ID
  def create_video(payload:, task_id:)
    raise Error, "missing_task_id" if task_id.blank?

    request(
      method: :post,
      endpoint: CONFIGURATION.dig(:endpoints, :videos),
      payload:,
      headers: { "X-Task-ID" => task_id }
    )
  end

  # Reads one page of tasks for recovering a submission by its request ID.
  #
  # @param page [Integer] the one-based page number
  # @param page_size [Integer] the maximum number of tasks to return
  # @return [Hash] the task page and pagination metadata
  def tasks(page:, page_size:)
    query = URI.encode_www_form(page:, page_size:)
    endpoint = "#{CONFIGURATION.dig(:endpoints, :tasks)}?#{query}"
    request(method: :get, endpoint:)
  end

  # Reads a task status by the provider task ID.
  #
  # @param task_id [String] the task identifier returned by MPT
  # @return [Hash] the current task status and generated output references
  def task(task_id:)
    encoded_task_id = URI.encode_www_form_component(task_id.to_s)
    endpoint = "#{CONFIGURATION.dig(:endpoints, :tasks)}/#{encoded_task_id}"
    request(method: :get, endpoint:)
  end

  # Downloads an MPT task artifact into the supplied IO from the configured host.
  #
  # @param file_path [String] the task-relative artifact reference returned by MPT
  # @param task_id [String] the saved provider task that owns the artifact
  # @param destination [IO] the tempfile or file that receives the artifact bytes
  # @return [IO] the destination rewound to the start of the downloaded artifact
  def download(file_path:, task_id:, destination:)
    relative_path = step_download_relative_path(file_path, task_id)
    raise Error, "invalid_file_path" unless relative_path

    endpoint = "#{CONFIGURATION.dig(:endpoints, :download).to_s.sub(%r{/+\z}, "")}/#{relative_path}"
    request(method: :get, endpoint:, destination:)
    destination.rewind
    destination
  end

  private

  def request(method:, endpoint:, payload: nil, headers: {}, destination: nil)
    api_key = CONFIGURATION.fetch(:api_key).to_s
    raise Error, "missing_api_key" if api_key.blank?

    base_url = "#{CONFIGURATION.fetch(:base_url).to_s.sub(%r{/+\z}, "")}/"
    uri = URI.join(base_url, endpoint.to_s.delete_prefix("/"))
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri.request_uri)
    http_request["x-api-key"] = api_key
    http_request["Accept"] = "application/json"
    headers.each { |name, value| http_request[name] = value }
    if payload
      http_request["Content-Type"] = "application/json"
      http_request.body = JSON.generate(payload)
    end

    downloaded_bytes = 0
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIGURATION.fetch(:open_timeout_seconds),
      read_timeout: CONFIGURATION.fetch(:read_timeout_seconds)
    ) do |http|
      if destination
        http.request(http_request) do |http_response|
          http_response.read_body do |chunk|
            downloaded_bytes += chunk.bytesize
            raise Error, "download_too_large" if downloaded_bytes > CONFIGURATION.fetch(:download_max_bytes)

            destination.write(chunk)
          end
        end
      else
        http.request(http_request)
      end
    end
    raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
    raise Error, "empty_download" if destination && downloaded_bytes.zero?
    return destination if destination

    parsed_response = JSON.parse(response.body.presence || "{}")
    raise Error, "invalid_response" unless parsed_response.is_a?(Hash)
    raise Error, "provider_#{parsed_response['status']}" if parsed_response["status"].to_i >= 400

    data = parsed_response.fetch("data", parsed_response)
    raise Error, "invalid_response" unless data.is_a?(Hash)

    data
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError
    raise Error, "invalid_endpoint"
  end

  def step_download_relative_path(file_path, task_id)
    return if task_id.blank?

    file_uri = URI.parse(file_path.to_s)
    base_uri = URI.parse(CONFIGURATION.fetch(:base_url).to_s)
    return if file_uri.query.present? || file_uri.fragment.present? || file_uri.userinfo.present?

    if file_uri.host.present?
      return unless file_uri.scheme == base_uri.scheme && file_uri.host == base_uri.host && file_uri.port == base_uri.port
    elsif file_uri.scheme.present?
      return
    end

    path = file_uri.path.to_s
    download_endpoint = CONFIGURATION.dig(:endpoints, :download).to_s.sub(%r{/+\z}, "")
    path = path.delete_prefix("#{download_endpoint}/") if path.start_with?("#{download_endpoint}/")
    path = path.delete_prefix("/")
    encoded_segments = path.split("/", -1)
    return if encoded_segments.length < 3

    segments = encoded_segments.map { |segment| URI::DEFAULT_PARSER.unescape(segment) }
    return unless segments.first == "tasks"
    return unless segments.second == task_id.to_s
    return if segments.any? do |segment|
      segment.blank? || [ ".", ".." ].include?(segment) || segment.match?(/[\/\\\x00-\x1F\x7F]/) || segment.match?(/%[0-9a-f]{2}/i)
    end

    segments.drop(1).map do |segment|
      URI.encode_www_form_component(segment).gsub("+", "%20")
    end.join("/")
  rescue URI::InvalidURIError
    nil
  end
end
