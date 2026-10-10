FactoryBot.define do
  factory :publication_quota_reservation do
    association :social_destination
    publication { association(:publication, social_destination:) }
    reserved_at { Time.current }
  end
end
