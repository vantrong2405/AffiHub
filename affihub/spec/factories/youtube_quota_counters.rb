FactoryBot.define do
  factory :youtube_quota_counter do
    bucket { "search.list" }
    usage_date { Time.current.in_time_zone(Rails.application.config_for(:youtube).deep_symbolize_keys.dig(:quota, :timezone)).to_date }
    requests_count { 1 }
  end
end
