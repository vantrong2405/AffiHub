# frozen_string_literal: true

FactoryBot.define do
  factory :social_connection do
    user
    provider { "facebook" }
    access_token { "social-token-value" }
  end
end
