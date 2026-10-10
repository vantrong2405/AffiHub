FactoryBot.define do
  factory :video_project do
    sequence(:name) { |index| "Video Project #{index}" }
  end
end
