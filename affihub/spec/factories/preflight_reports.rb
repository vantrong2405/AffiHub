FactoryBot.define do
  factory :preflight_report do
    association :render_version
    checked_destination_ids { [] }
    destination_results { {} }
    checked_at { Time.current }
  end
end
