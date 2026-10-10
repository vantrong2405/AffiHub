# frozen_string_literal: true

class Muapi::Client
  CONFIGURATION = Rails.application.config_for(:muapi).deep_symbolize_keys

  class Error < StandardError
    attr_reader :code

    # Initializes an estimate error without exposing provider response data.
    #
    # @param code [String] a safe error category
    # @return [Muapi::Client::Error] the sanitized provider error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Requests a dynamic MuAPI estimate using the exact video generation input.
  #
  # @param model_id [String] the configured MuAPI model identifier
  # @param prompt [String] the scene prompt
  # @param duration [Integer] the requested scene duration in seconds
  # @param resolution [String] the source video resolution
  # @param aspect_ratio [String] the requested video aspect ratio
  # @return [Hash] the provider's estimate response
  def estimate_cost(model_id:, prompt:, duration:, resolution:, aspect_ratio:)
    endpoint = format(
      CONFIGURATION.fetch(:estimate_cost_endpoint),
      model_id: URI.encode_www_form_component(model_id)
    )
    request(
      endpoint:,
      payload: { prompt:, duration:, resolution:, aspect_ratio: }
    )
  end

  private

  def request(endpoint:, payload:)
    api_key = CONFIGURATION.fetch(:api_key).to_s
    raise Error, "missing_api_key" if api_key.blank?

    base_url = "#{CONFIGURATION.fetch(:base_url).to_s.sub(%r{/+\z}, "")}/"
    uri = URI.join(base_url, endpoint.to_s.delete_prefix("/"))
    http_request = Net::HTTP::Post.new(uri.request_uri)
    http_request["x-api-key"] = api_key
    http_request["Accept"] = "application/json"
    http_request["Content-Type"] = "application/json"
    http_request.body = JSON.generate(payload)
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIGURATION.fetch(:open_timeout_seconds),
      read_timeout: CONFIGURATION.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)

    estimate = JSON.parse(response.body.presence || "{}")
    raise Error, "invalid_json_response" unless estimate.is_a?(Hash)

    estimate
  rescue JSON::ParserError
    raise Error, "invalid_json_response"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError, KeyError, ArgumentError
    raise Error, "invalid_estimate_request"
  end
end
