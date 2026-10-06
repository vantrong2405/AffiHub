FactoryBot.define do
  factory :render_version do
    association :source_asset
    version_number { 1 }
    edit_config { {} }
    metadata { {} }
  end
end
