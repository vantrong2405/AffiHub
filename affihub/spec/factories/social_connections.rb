FactoryBot.define do
  factory :social_connection do
    provider { "facebook" }
    external_user_id { SecureRandom.uuid }
    name { "AffiHub Page Owner" }
    access_token { "user-access-token" }
    status { "connected" }
  end
end
