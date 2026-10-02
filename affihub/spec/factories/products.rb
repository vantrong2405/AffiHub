# frozen_string_literal: true

FactoryBot.define do
  factory :product do
    user
    affiliate_provider { "accesstrade" }
    sequence(:source_product_id) { |n| "sp-#{n}" }
    merchant { "Sample Merchant" }
    title { "Sample Product" }
  end
end
