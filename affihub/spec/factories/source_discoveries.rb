FactoryBot.define do
  factory :source_discovery do
    association :video_project
    search_type { "keyword" }
    search_query { "video query" }
    region_code { "VN" }
    video_category_id { nil }
    searched_at { Time.current }
  end

  factory :source_discovery_result do
    association :source_discovery
    association :youtube_discovery_metadata
    sequence(:position)
  end
end
