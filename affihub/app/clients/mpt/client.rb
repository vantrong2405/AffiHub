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
  # @return [Hash] the provider response containing the task ID
  def create_video(payload:)
    request(method: :post, endpoint: CONFIGURATION.dig(:endpoints, :videos), payload:)
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

  private

  def request(method:, endpoint:, payload: nil)
    api_key = CONFIGURATION.fetch(:api_key).to_s
    raise Error, "missing_api_key" if api_key.blank?

    base_url = "#{CONFIGURATION.fetch(:base_url).to_s.sub(%r{/+\z}, "")}/"
    uri = URI.join(base_url, endpoint.to_s.delete_prefix("/"))
    request_class = Net::HTTP.const_get(method.to_s.capitalize)
    http_request = request_class.new(uri.request_uri)
    http_request["x-api-key"] = api_key
    http_request["Accept"] = "application/json"
    if payload
      http_request["Content-Type"] = "application/json"
      http_request.body = JSON.generate(payload)
    end

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIGURATION.fetch(:open_timeout_seconds),
      read_timeout: CONFIGURATION.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
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
end
