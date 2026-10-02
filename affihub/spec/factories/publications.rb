# frozen_string_literal: true

FactoryBot.define do
  factory :publication do
    content
    social_destination
    status { "draft" }
    attempt_count { 0 }
  end
end
