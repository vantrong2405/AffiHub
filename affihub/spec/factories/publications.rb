FactoryBot.define do
  factory :publication do
    association :render_version
    association :social_destination
    caption { "Bản dựng thử của AffiHub" }
    status { "draft" }
  end
end
