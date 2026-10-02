# frozen_string_literal: true

FactoryBot.define do
  factory :content do
    product
    user
    status { "generated" }
    affiliate_url { "https://example.com/aff/sample" }
  end
end
