# frozen_string_literal: true

FactoryBot.define do
  factory :ai_connection do
    user
    access_token { "access-token-value" }
    refresh_token { "refresh-token-value" }
    access_token_expires_at { 1.hour.from_now }
    status { "connected" }
  end
end
