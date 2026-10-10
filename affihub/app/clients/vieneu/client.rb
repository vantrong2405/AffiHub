# frozen_string_literal: true

class Vieneu::Client
  CONFIGURATION = Rails.application.config_for(:vieneu).deep_symbolize_keys

  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe error category
    # @return [Vieneu::Client::Error] the sanitized provider error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Synthesizes Vietnamese speech as WAV using the configured VieNeu model.
  #
  # @param text [String] the text to synthesize
  # @param voice [String] the configured VieNeu voice
  # @return [String] the generated WAV bytes
  def synthesize(text:, voice:)
    api_key = CONFIGURATION.fetch(:api_key).to_s
    response_format = CONFIGURATION.fetch(:response_format)
    raise Error, "unsupported_response_format" unless response_format == "wav"

    headers = { "Accept" => "audio/wav", "Content-Type" => "application/json" }
    headers["Authorization"] = "Bearer #{api_key}" if api_key.present?

    audio_data = request(
      endpoint: CONFIGURATION.fetch(:speech_endpoint),
      headers:,
      payload: {
        model: CONFIGURATION.fetch(:model_id),
        input: text,
        voice:,
        response_format:,
        speed: CONFIGURATION.fetch(:speed)
      }
    )
    raise Error, "invalid_wav_response" unless wav_audio?(audio_data)

    audio_data
  end

  private

  def request(endpoint:, headers:, payload:)
    base_url = "#{CONFIGURATION.fetch(:base_url).to_s.sub(%r{/+\z}, "")}/"
    uri = URI.join(base_url, endpoint.to_s.delete_prefix("/"))
    http_request = Net::HTTP::Post.new(uri.request_uri, headers)
    http_request.body = JSON.generate(payload)
    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIGURATION.fetch(:open_timeout_seconds),
      read_timeout: CONFIGURATION.fetch(:read_timeout_seconds)
    ) { |http| http.request(http_request) }
    raise Error, "http_#{response.code}" unless response.is_a?(Net::HTTPSuccess)
    raise Error, "empty_audio_response" if response.body.blank?

    response.body
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
    raise Error, "network_request_failed"
  rescue URI::InvalidURIError, KeyError, ArgumentError
    raise Error, "invalid_tts_request"
  end

  def wav_audio?(audio_data)
    audio_data.is_a?(String) && audio_data.bytesize >= 12 &&
      audio_data.byteslice(0, 4) == "RIFF" && audio_data.byteslice(8, 4) == "WAVE"
  end
end
