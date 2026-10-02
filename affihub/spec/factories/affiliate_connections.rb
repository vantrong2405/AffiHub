# frozen_string_literal: true

FactoryBot.define do
  factory :affiliate_connection do
    user
    provider { "accesstrade" }
    api_key { "api-key-value" }
  end
end
