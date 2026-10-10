require "rails_helper"

RSpec.describe "Google connections", type: :request do
  describe "GET /google_connections" do
    it "returns the optional Google integration settings" do
      get google_connections_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /google_connections/:id" do
    it "returns the Drive folder configuration without exposing tokens" do
      google_connection = create(:google_connection, integration: "drive")
      google_client = instance_double(Google::Client, list_drive_folders: [])
      allow(Google::Client).to receive(:new).with(access_token: google_connection.access_token).and_return(google_client)

      get google_connection_path(google_connection)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(Regexp.escape(google_connection.access_token))
    end

    it "returns the Sheets configuration with the selected spreadsheet tabs" do
      google_connection = create(
        :google_connection,
        integration: "sheets"
      )
      google_client = instance_double(
        Google::Client,
        spreadsheet_worksheets: [ { "sheetId" => 0, "title" => "Lịch đăng", "index" => 0 } ]
      )
      allow(Google::Client).to receive(:new).with(access_token: google_connection.access_token).and_return(google_client)

      get google_connection_path(google_connection), params: {
        spreadsheet_id: "spreadsheet-1234567890"
      }

      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /google_connections/:id" do
    it "returns to the Drive connection after saving its selected folder" do
      google_connection = create(:google_connection, integration: "drive")
      google_client = instance_double(
        Google::Client,
        find_drive_folder: { "id" => "folder-123", "mimeType" => "application/vnd.google-apps.folder" }
      )
      allow(Google::Client).to receive(:new).with(access_token: google_connection.access_token).and_return(google_client)

      patch google_connection_path(google_connection), params: {
        google_connection: { drive_parent_folder_id: "folder-123" }
      }

      expect(response).to redirect_to(google_connection_path(google_connection))
      expect(google_connection.reload.drive_parent_folder_id).to eq("folder-123")
    end
  end
end
