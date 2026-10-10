FactoryBot.define do
  factory :drive_export do
    association :google_connection
    association :render_version
    folder_key { "video-project-#{render_version.video_project_id}" }
    file_key { "render-version-#{render_version.id}" }
    status { "queued" }
  end
end
