FactoryBot.define do
  factory :ai_generation do
    association :video_project
    correlation_id { SecureRandom.uuid }
    input_snapshot { {} }
    estimate_snapshot { {} }
    consent_snapshot { {} }
    actual_costs { {} }
  end
end
