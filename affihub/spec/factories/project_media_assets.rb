FactoryBot.define do
  factory :project_media_asset do
    association :video_project

    after(:build) do |project_media_asset|
      next if project_media_asset.file.attached?

      project_media_asset.file.attach(
        io: StringIO.new(File.binread(Rails.root.join("spec/fixtures/files/brand.png"))),
        filename: "brand.png",
        content_type: "image/png"
      )
    end
  end
end
