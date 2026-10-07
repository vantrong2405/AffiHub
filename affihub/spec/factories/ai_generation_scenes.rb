FactoryBot.define do
  factory :ai_generation_scene do
    association :ai_generation
    sequence(:scene_index) { |index| index - 1 }
    narration_snapshot { "A short summer skincare story." }
    voice_name { "vi-VN-HoaiMyNeural" }
    estimate_snapshot do
      {
        provider: "azure_speech",
        amount: "0.01",
        currency: "USD",
        source: "Azure Speech pricing estimate",
        estimated_at: 1.minute.ago.iso8601,
        input_snapshot: { narration: narration_snapshot, voice: voice_name }
      }
    end
    consent_snapshot do
      {
        confirmed: true,
        confirmed_at: 1.minute.ago.iso8601,
        estimate: estimate_snapshot
      }
    end
    actual_costs { {} }
  end
end
