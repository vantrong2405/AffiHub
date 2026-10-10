FactoryBot.define do
  factory :render_version do
    association :video_project
    source_asset do
      association(:source_asset, video_project: video_project, status: "ready")
    end
  end
end
