# frozen_string_literal: true

require "cgi"

class AzureSpeech::Client
  CONFIGURATION = Rails.application.config_for(:azure_speech).deep_symbolize_keys

  class Error < StandardError
    attr_reader :code

    # Initializes a provider error without exposing response data or credentials.
    #
    # @param code [String] a safe error category
    # @return [AzureSpeech::Client::Error] the sanitized provider error
    def initialize(code)
      @code = code
      super(code)
    end
  end

  # Synthesizes SSML speech through the configured Azure Speech resource.
  #
  # @param text [String] the text to synthesize
  # @param voice [String] the Azure voice identifier
  # @return [String] the generated WAV bytes
  def synthesize(text:, voice:)
    raise Error, "provider_not_configured" unless configured?

    audio_data = request(
      endpoint: CONFIGURATION.fetch(:endpoint),
      headers: request_headers,
      body: speech_markup(text:, voice:)
    )
    raise Error, "invalid_wav_response" unless wav_audio?(audio_data)

    audio_data
  end

  private

  def configured?
    CONFIGURATION[:endpoint].present? && CONFIGURATION[:api_key].present? && CONFIGURATION[:region].present?
  end

  def request_headers
    {
      "Accept" => "audio/wav",
      "Content-Type" => "application/ssml+xml",
      "Ocp-Apim-Subscription-Key" => CONFIGURATION.fetch(:api_key),
      "Ocp-Apim-Subscription-Region" => CONFIGURATION.fetch(:region),
      "X-Microsoft-OutputFormat" => CONFIGURATION.fetch(:output_format)
    }
  end

  def speech_markup(text:, voice:)
    language = voice.split("-").first(2).join("-")
    safe_text = CGI.escapeHTML(text.to_s)
    safe_voice = CGI.escapeHTML(voice.to_s)
    "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xml:lang=\"#{language}\"><voice name=\"#{safe_voice}\">#{safe_text}</voice></speak>"
  end

  def request(endpoint:, headers:, body:)
    uri = URI.parse(endpoint)
    http_request = Net::HTTP::Post.new(uri.request_uri, headers)
    http_request.body = body
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
