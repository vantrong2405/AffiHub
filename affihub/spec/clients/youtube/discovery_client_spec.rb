# frozen_string_literal: true

require "rails_helper"

RSpec.describe Youtube::DiscoveryClient, type: :client do
  describe "#search_videos" do
    it "uses the official video keyword search endpoint" do
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/search")
        .with(query: {
          "part" => "snippet",
          "q" => "cooking",
          "type" => "video",
          "regionCode" => "VN",
          "maxResults" => "25"
        })
        .to_return(
          status: 200,
          body: {
            items: [
              {
                id: { videoId: "video-123" },
                snippet: {
                  title: "Home cooking",
                  channelTitle: "Kitchen",
                  thumbnails: { high: { url: "https://i.ytimg.com/vi/video-123/hqdefault.jpg" } }
                }
              }
            ]
          }.to_json
        )

      result = described_class.new.search_videos(query: "cooking")

      expect(request).to have_been_made.once
      expect(YoutubeQuotaCounter.find_by!(bucket: "search.list").requests_count).to eq(1)
      expect(result).to eq([
        {
          video_id: "video-123",
          title: "Home cooking",
          channel_title: "Kitchen",
          thumbnail_url: "https://i.ytimg.com/vi/video-123/hqdefault.jpg",
          attribution_url: "https://www.youtube.com/watch?v=video-123"
        }
      ])
    end

    it "raises a local quota error without sending a request when search.list is exhausted" do
      configuration = Rails.application.config_for(:youtube).deep_symbolize_keys
      bucket = configuration.dig(:quota, :buckets, :search_list)
      create(:youtube_quota_counter, bucket: bucket.fetch(:method), requests_count: bucket.fetch(:daily_limit))
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/search")

      expect do
        described_class.new.search_videos(query: "cooking")
      end.to raise_error(described_class::Error, "quota_exhausted")

      expect(request).not_to have_been_made
    end
  end

  describe "#popular_videos" do
    it "uses the regional and category most-popular chart endpoint" do
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: {
          "part" => "snippet",
          "chart" => "mostPopular",
          "regionCode" => "VN",
          "maxResults" => "25",
          "videoCategoryId" => "10"
        })
        .to_return(
          status: 200,
          body: {
            items: [
              {
                id: "video-456",
                snippet: {
                  title: "Popular music video",
                  channelTitle: "Music",
                  thumbnails: { high: { url: "https://i.ytimg.com/vi/video-456/hqdefault.jpg" } }
                }
              }
            ]
          }.to_json
        )

      result = described_class.new.popular_videos(region_code: "VN", video_category_id: "10")

      expect(request).to have_been_made.once
      expect(YoutubeQuotaCounter.count).to eq(0)
      expect(result).to eq([
        {
          video_id: "video-456",
          title: "Popular music video",
          channel_title: "Music",
          thumbnail_url: "https://i.ytimg.com/vi/video-456/hqdefault.jpg",
          attribution_url: "https://www.youtube.com/watch?v=video-456"
        }
      ])
    end

    it "does not send a category filter when all categories are selected" do
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: {
          "part" => "snippet",
          "chart" => "mostPopular",
          "regionCode" => "VN",
          "maxResults" => "25"
        })
        .to_return(status: 200, body: { items: [] }.to_json)

      result = described_class.new.popular_videos(region_code: "VN")

      expect(request).to have_been_made.once
      expect(YoutubeQuotaCounter.count).to eq(0)
      expect(result).to eq([])
    end
  end
end
