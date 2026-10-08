# frozen_string_literal: true

require "rails_helper"

RSpec.describe Youtube::DiscoveryClient, type: :client do
  describe "#search_videos" do
    it "uses the official video keyword search endpoint" do
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/search")
        .with(query: hash_including("q" => "cooking", "type" => "video"))
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
  end

  describe "#popular_videos" do
    it "uses the regional and category most-popular chart endpoint" do
      request = stub_request(:get, "https://www.googleapis.com/youtube/v3/videos")
        .with(query: hash_including(
          "chart" => "mostPopular",
          "regionCode" => "VN",
          "videoCategoryId" => "10"
        ))
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
  end
end
