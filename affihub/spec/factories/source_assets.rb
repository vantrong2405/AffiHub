FactoryBot.define do
  factory :source_asset do
    association :video_project
    source_type { "upload" }
    provenance { {} }
  end
end
