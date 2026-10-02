# frozen_string_literal: true

require "net/http"
require "json"

# Creates ACCESSTRADE tracking links for existing product URLs.
class AccesstradeClient
  CONFIG = Rails.application.config_for(:accesstrade)

  class RequestError < StandardError; end

  # Creates affiliate links for the supplied product URLs.
  #
  # @param urls [Array<String>] product URLs accepted by ACCESSTRADE
  # @param token [String] ACCESSTRADE API token
  # @return [Hash{String => Hash<String, String>}] links keyed by their original URL
  # @raise [RequestError] when ACCESSTRADE rejects the request or returns invalid JSON
  def create_affiliate_links(urls:, token:)
    batches = urls.each_slice(CONFIG.batch_size).to_a
    batches.each_with_index.each_with_object({}) do |(batch, index), mapped|
      response = request_with_retry(
        URI.join(CONFIG.base_url, CONFIG.link_path).to_s,
        body: {
          campaign_id: CONFIG.campaign_id,
          urls: batch,
          utm_source: CONFIG.utm_source
        },
        headers: { "Authorization" => "Token #{token}" }
      )

      success_links = JSON.parse(response.body).dig("data", "success_link") || []
      success_links.each do |link|
        mapped[link.fetch("url_origin")] = {
          "aff_link" => link["aff_link"],
          "short_link" => link["short_link"]
        }
      end
      sleep(CONFIG.batch_delay_seconds) if index < batches.length - 1
    end
  rescue JSON::ParserError, KeyError => error
    raise RequestError, "ACCESSTRADE returned an invalid link response: #{error.class}"
  end

  private

  # Retries transient provider and network failures with exponential backoff.
  #
  # @param url [String] configured absolute endpoint URL
  # @param body [Hash] request payload
  # @param headers [Hash<String, String>] request headers
  # @return [Net::HTTPResponse] a successful provider response
  # @raise [RequestError] when the provider keeps rejecting the request
  def request_with_retry(url, body:, headers: {})
    attempt = 0
    begin
      response = request(url, body: body, headers: headers)
      return response if response.is_a?(Net::HTTPSuccess)
      raise RequestError, "ACCESSTRADE returned #{response.code}" unless response.code.to_i >= 500 || response.code.to_i == 429
      raise RequestError, "ACCESSTRADE returned #{response.code}"
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, SocketError, RequestError => error
      raise if error.is_a?(RequestError) && !error.message.match?(/returned (?:5\d\d|429)\z/)
      raise if attempt >= CONFIG.retries

      sleep(CONFIG.retry_backoff_seconds * (2**attempt))
      attempt += 1
      retry
    end
  end

  # Sends a JSON POST through the client's shared HTTP transport.
  #
  # @param url [String] configured absolute endpoint URL
  # @param body [Hash] request payload
  # @param headers [Hash<String, String>] request headers
  # @return [Net::HTTPResponse] the raw provider response
  def request(url, body:, headers: {})
    uri = URI(url)
    http_request = Net::HTTP::Post.new(uri)
    http_request["Content-Type"] = "application/json"
    headers.each { |key, value| http_request[key] = value }
    http_request.body = body.to_json

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: CONFIG.timeout,
      read_timeout: CONFIG.timeout,
      write_timeout: CONFIG.timeout
    ) { |http| http.request(http_request) }
  end
end
