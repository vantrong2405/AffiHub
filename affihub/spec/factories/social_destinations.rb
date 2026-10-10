FactoryBot.define do
  factory :social_destination do
    association :social_connection
    provider { "facebook" }
    external_id { SecureRandom.uuid }
    name { "AffiHub Test Page" }
    access_token { "page-access-token" }
    status { "connected" }
  end
end
