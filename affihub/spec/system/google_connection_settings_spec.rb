require "rails_helper"

RSpec.describe "Google connection settings", type: :system do
  it "persists the selected Drive folder without displaying OAuth secrets" do
    google_connection = create(:google_connection, integration: "drive")
    drive_fields = "id,name,mimeType,webViewLink"
    folder_mime_type = "application/vnd.google-apps.folder"

    stub_request(:get, "https://www.googleapis.com/drive/v3/files")
      .with(
        query: {
          "fields" => "files(#{drive_fields})",
          "pageSize" => "100",
          "q" => "mimeType = '#{folder_mime_type}' and trashed = false"
        },
        headers: { "Authorization" => "Bearer google-access-token" }
      )
      .to_return(body: {
        files: [ { id: "folder-123", name: "Chiến dịch video", mimeType: folder_mime_type } ]
      }.to_json)

    stub_request(:get, "https://www.googleapis.com/drive/v3/files/folder-123")
      .with(
        query: { "fields" => drive_fields },
        headers: { "Authorization" => "Bearer google-access-token" }
      )
      .to_return(body: { id: "folder-123", name: "Chiến dịch video", mimeType: folder_mime_type }.to_json)

    visit google_connection_path(google_connection)
    select "Chiến dịch video", from: "Vị trí trên Google Drive"
    click_button "Lưu cấu hình Drive"

    expect(page).to have_content("Đã lưu cấu hình đồng bộ Google.")
    expect(google_connection.reload.drive_parent_folder_id).to eq("folder-123")
    expect(page).not_to have_content("google-access-token")
  end

  it "shows a reconnect state without displaying an expired access token" do
    google_connection = create(:google_connection, integration: "sheets", status: "reauth_required")

    visit google_connection_path(google_connection)

    expect(page).to have_content("Cần kết nối lại")
    expect(page).to have_button("Kết nối lại với Google")
    expect(page).not_to have_content("google-access-token")
  end
end
