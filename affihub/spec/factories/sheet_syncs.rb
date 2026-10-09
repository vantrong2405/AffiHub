FactoryBot.define do
  factory :sheet_sync do
    association :google_connection, integration: "sheets", spreadsheet_id: "spreadsheet-42", worksheet_title: "Nội dung"
    association :render_version
    association :social_destination
    sheet_row_key do
      "affihub-project-#{render_version.video_project_id}-render-#{render_version.id}-destination-#{social_destination.id}"
    end
    status { "queued" }
  end
end
