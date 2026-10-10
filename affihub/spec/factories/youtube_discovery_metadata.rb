FactoryBot.define do
  factory :youtube_discovery_metadata do
    video_id { SecureRandom.hex(8) }
    title { "Video title" }
    channel_title { "Channel title" }
    thumbnail_url { "https://i.ytimg.com/vi/video-123/hqdefault.jpg" }
    attribution_url { "https://www.youtube.com/watch?v=video-123" }
    discovery_type { "keyword" }
    search_query { "video query" }
    region_code { "VN" }
    video_category_id { nil }
    fetched_at { Time.current }
  end
end
