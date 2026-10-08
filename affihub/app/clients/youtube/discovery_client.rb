# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Youtube
  class DiscoveryClient
    CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys

    class Error < StandardError
      attr_reader :code

      # Initializes a discovery error without exposing provider response data.
      #
      # @param code [String] a safe error category
      # @return [Youtube::DiscoveryClient::Error] the sanitized API error
      def initialize(code)
        @code = code
        super(code)
      end
    end

    # Searches for videos with YouTube's official keyword search endpoint.
    #
    # @param query [String] the user-entered keyword query
    # @return [Array<Hash>] normalized video metadata and attribution URLs
    def search_videos(query:)
      response = request(
        endpoint: CONFIGURATION.fetch(:search_endpoint),
        params: {
          part: "snippet",
          q: query,
          type: "video",
          regionCode: CONFIGURATION.fetch(:default_region_code),
          maxResults: CONFIGURATION.fetch(:max_results)
        }
      )
      step_map_videos(response.fetch("items", []), search_results: true)
    end

    # Reads the official region and category most-popular chart.
    #
    # @param region_code [String] ISO country code used for the chart
    # @param video_category_id [String] YouTube video category identifier
    # @return [Array<Hash>] normalized video metadata and attribution URLs
    def popular_videos(region_code:, video_category_id:)
      response = request(
        endpoint: CONFIGURATION.fetch(:videos_endpoint),
        params: {
          part: "snippet",
          chart: "mostPopular",
          regionCode: region_code,
          videoCategoryId: video_category_id,
          maxResults: CONFIGURATION.fetch(:max_results)
        }
      )
      step_map_videos(response.fetch("items", []), search_results: false)
    end

    private

    def request(endpoint:, params:)
      api_key = CONFIGURATION.fetch(:api_key).to_s
      raise Error, "api_key_not_configured" if api_key.blank?

      uri = URI.join(
        "#{CONFIGURATION.fetch(:api_base_url).sub(%r{/+\z}, "")}/",
        "#{CONFIGURATION.fetch(:api_version)}/#{endpoint}"
      )
      uri.query = URI.encode_www_form(params)
      http_request = Net::HTTP::Get.new(uri)
      http_request["X-Goog-Api-Key"] = api_key
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: CONFIGURATION.fetch(:open_timeout_seconds),
        read_timeout: CONFIGURATION.fetch(:read_timeout_seconds)
      ) { |http| http.request(http_request) }
      parsed_response = JSON.parse(response.body.presence || "{}")
      raise Error, step_safe_error_code(response, parsed_response) unless response.is_a?(Net::HTTPSuccess)

      parsed_response
    rescue JSON::ParserError
      raise Error, "invalid_json_response"
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError
      raise Error, "network_request_failed"
    rescue URI::InvalidURIError, KeyError, ArgumentError
      raise Error, "invalid_api_request"
    end

    def step_map_videos(items, search_results:)
      items.filter_map do |item|
        video_id = search_results ? item.dig("id", "videoId") : item["id"]
        next if video_id.blank?

        snippet = item.fetch("snippet", {})
        {
          video_id:,
          title: snippet["title"].to_s,
          channel_title: snippet["channelTitle"].to_s,
          thumbnail_url: step_thumbnail_url(snippet.fetch("thumbnails", {}), video_id),
          attribution_url: "https://www.youtube.com/watch?v=#{URI.encode_www_form_component(video_id)}"
        }
      end
    end

    def step_thumbnail_url(thumbnails, video_id)
      thumbnails.dig("high", "url") ||
        thumbnails.dig("medium", "url") ||
        thumbnails.dig("default", "url") ||
        "https://i.ytimg.com/vi/#{URI.encode_www_form_component(video_id)}/default.jpg"
    end

    def step_safe_error_code(response, parsed_response)
      reasons = parsed_response.dig("error", "errors").to_a.filter_map { |error| error["reason"] }
      return "rate_limited" if (reasons & %w[rateLimitExceeded userRateLimitExceeded]).any?
      return "quota_exhausted" if reasons.include?("quotaExceeded")

      "http_#{response.code}"
    end
  end
end
