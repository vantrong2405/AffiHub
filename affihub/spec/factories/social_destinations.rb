# frozen_string_literal: true

FactoryBot.define do
  factory :social_destination do
    social_connection
    destination_type { "page" }
    sequence(:page_id) { |n| "page-#{n}" }
    name { "Sample Page" }
    page_access_token { "page-token-value" }
  end
end
