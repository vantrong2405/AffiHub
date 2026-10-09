require "rails_helper"

RSpec.describe "Google::Client", type: :service do
  describe "#create_folder" do
    let(:google_client_class) { Google::Client }
    let(:google_client) { google_client_class.new(access_token: "google-access-secret") }

    it "returns a folder request with inherited permissions and no public permission override" do
      request = stub_request(:post, %r{https://www\.googleapis\.com/drive/v3/files})
        .with(
          headers: { "Authorization" => "Bearer google-access-secret" },
          body: JSON.generate(
            "name" => "Dự án mùa hè",
            "mimeType" => "application/vnd.google-apps.folder",
            "appProperties" => { "affihubFolderKey" => "project-42" }
          )
        )
        .to_return(
          status: 200,
          body: { id: "drive-folder-42", name: "Dự án mùa hè" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      google_client.create_folder(folder_key: "project-42", name: "Dự án mùa hè", parent_id: nil)

      expect(request).to have_been_requested.once
    end
  end

  describe "#request" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }

    context "when Google reports the standard daily quota is exhausted" do
      before do
        stub_request(:post, %r{https://www\.googleapis\.com/drive/v3/files})
          .to_return(
            status: 403,
            body: {
              error: {
                code: 403,
                errors: [ { reason: "dailyLimitExceeded" } ],
                message: "Daily Limit Exceeded"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises a typed quota error that the Drive worker can leave waiting" do
        expect do
          google_client.create_folder(folder_key: "project-42", name: "Dự án mùa hè", parent_id: nil)
        end.to raise_error(Google::Client::DailyQuotaExceeded) { |error|
          expect(error.status).to eq(403)
          expect(error.reason).to eq("dailyLimitExceeded")
        }
      end
    end

    context "when Google reports the account storage is full" do
      before do
        stub_request(:post, %r{https://www\.googleapis\.com/drive/v3/files})
          .to_return(
            status: 403,
            body: {
              error: {
                code: 403,
                errors: [ { reason: "storageQuotaExceeded" } ],
                message: "Storage quota exceeded"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises a typed storage error without converting it to a retryable quota error" do
        expect do
          google_client.create_folder(folder_key: "project-42", name: "Dự án mùa hè", parent_id: nil)
        end.to raise_error(Google::Client::StorageQuotaExceeded) { |error|
          expect(error.status).to eq(403)
          expect(error.reason).to eq("storageQuotaExceeded")
        }
      end
    end

    context "when Google reports a temporary rate limit" do
      before do
        stub_request(:post, %r{https://www\.googleapis\.com/drive/v3/files})
          .to_return(
            status: 429,
            body: {
              error: {
                code: 429,
                errors: [ { reason: "rateLimitExceeded" } ],
                message: "Rate limit exceeded"
              }
            }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises a retryable rate limit error for bounded worker backoff" do
        expect do
          google_client.create_folder(folder_key: "project-42", name: "Dự án mùa hè", parent_id: nil)
        end.to raise_error(Google::Client::RateLimitError) { |error|
          expect(error.status).to eq(429)
          expect(error.reason).to eq("rateLimitExceeded")
        }
      end
    end
  end

  describe "#create_upload_session" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }
    let(:session_uri) { "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=private-session" }

    it "returns a resumable session URI for a private file with the stable app property" do
      request = stub_request(:post, "https://www.googleapis.com/upload/drive/v3/files")
        .with(
          query: { "uploadType" => "resumable", "fields" => "id,name,mimeType,webViewLink,appProperties" },
          headers: {
            "Authorization" => "Bearer google-access-secret",
            "X-Upload-Content-Type" => "video/mp4",
            "X-Upload-Content-Length" => "12"
          },
          body: JSON.generate(
            "name" => "render-export-42.mp4",
            "mimeType" => "video/mp4",
            "parents" => [ "drive-folder-1" ],
            "appProperties" => { "affihubFileKey" => "export-42" }
          )
        )
        .to_return(status: 200, headers: { "Location" => session_uri })

      result = google_client.create_upload_session(
        folder_id: "drive-folder-1",
        file_key: "export-42",
        file_name: "render-export-42.mp4",
        file_size: 12
      )

      expect(result).to eq(session_uri)
      expect(request).to have_been_requested.once
    end
  end

  describe "#upload_file" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }
    let(:session_uri) { "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=private-session" }
    let(:file) { StringIO.new("render-data") }

    it "uploads the file bytes through the resumable session without sending the OAuth token again" do
      request = stub_request(:put, session_uri)
        .with do |request|
          request.headers["Authorization"].nil? &&
            request.headers["Content-Length"] == "11" &&
            request.headers["Content-Type"] == "video/mp4" &&
            request.body == "render-data"
        end
        .to_return(
          status: 200,
          body: { id: "drive-file-1", webViewLink: "https://drive.google.com/file/d/file-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = google_client.upload_file(session_uri:, file:, file_size: 11)

      expect(result).to eq("id" => "drive-file-1", "webViewLink" => "https://drive.google.com/file/d/file-1")
      expect(request).to have_been_requested.once
    end

    it "resumes from Google's confirmed byte range after an incomplete upload" do
      initial_upload = stub_request(:put, session_uri)
        .with(body: "render-data")
        .to_return(status: 308, headers: { "Range" => "bytes=0-3" })
      status_check = stub_request(:put, session_uri)
        .with(
          headers: {
            "Content-Length" => "0",
            "Content-Range" => "bytes */11"
          },
          body: ""
        )
        .to_return(status: 308, headers: { "Range" => "bytes=0-3" })
      resumed_upload = stub_request(:put, session_uri)
        .with(
          headers: {
            "Content-Length" => "7",
            "Content-Range" => "bytes 4-10/11"
          },
          body: "er-data"
        )
        .to_return(
          status: 200,
          body: { id: "drive-file-1" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = google_client.upload_file(session_uri:, file:, file_size: 11)

      expect(result).to eq("id" => "drive-file-1")
      expect(initial_upload).to have_been_requested.once
      expect(status_check).to have_been_requested.once
      expect(resumed_upload).to have_been_requested.once
    end
  end

  describe "#upsert_sheet_row" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }
    let(:row_key) { "affihub-render-42-destination-9" }
    let(:row_values) { [ row_key, "Chiến dịch", "42", "Facebook" ] }

    it "returns the existing row number and updates the row using RAW values" do
      lookup = stub_request(:get, %r{https://sheets\.googleapis\.com/v4/spreadsheets/spreadsheet-42/values/})
        .with(headers: { "Authorization" => "Bearer google-access-secret" })
        .to_return(
          status: 200,
          body: { values: [ [ "header" ], [ row_key, "Bản cũ" ] ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      update = stub_request(:put, %r{https://sheets\.googleapis\.com/v4/spreadsheets/spreadsheet-42/values/})
        .with(query: { "valueInputOption" => "RAW" }, body: { values: [ row_values ] }.to_json)
        .to_return(
          status: 200,
          body: { updatedRange: "Nội dung!A2:M2", updatedRows: 1 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = google_client.upsert_sheet_row(
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung",
        row_key:,
        values: row_values
      )

      expect(result).to eq(2)
      expect(lookup).to have_been_requested.once
      expect(update).to have_been_requested.once
    end

    it "returns the appended row number and writes RAW values when the key is absent" do
      lookup = stub_request(:get, %r{https://sheets\.googleapis\.com/v4/spreadsheets/spreadsheet-42/values/})
        .to_return(
          status: 200,
          body: { values: [ [ "another-row" ] ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      append = stub_request(:post, %r{https://sheets\.googleapis\.com/v4/spreadsheets/spreadsheet-42/values/})
        .with(
          query: { "insertDataOption" => "INSERT_ROWS", "valueInputOption" => "RAW" },
          body: { values: [ row_values ] }.to_json
        )
        .to_return(
          status: 200,
          body: { updates: { updatedRange: "Nội dung!A3:M3", updatedRows: 1 } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = google_client.upsert_sheet_row(
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung",
        row_key:,
        values: row_values
      )

      expect(result).to eq(3)
      expect(lookup).to have_been_requested.once
      expect(append).to have_been_requested.once
    end

    it "returns a typed free-quota exhaustion when Sheets refuses the standard quota request" do
      request = stub_request(
        :get,
        %r{https://sheets\.googleapis\.com/v4/spreadsheets/spreadsheet-42/values/}
      ).to_return(
        status: 403,
        body: {
          error: {
            code: 403,
            errors: [ { reason: "quotaExceeded" } ],
            message: "Quota exceeded"
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      expect do
        google_client.upsert_sheet_row(
          spreadsheet_id: "spreadsheet-42",
          worksheet_title: "Nội dung",
          row_key:,
          values: row_values
        )
      end.to raise_error(Google::Client::DailyQuotaExceeded) { |error|
        expect(error.reason).to eq("quotaExceeded")
      }
      expect(request).to have_been_requested.once
    end
  end

  describe "#spreadsheet_worksheets" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }

    it "returns only worksheet IDs and titles from the selected spreadsheet" do
      request = stub_request(
        :get,
        "https://sheets.googleapis.com/v4/spreadsheets/spreadsheet-42"
      ).with(
        query: { "fields" => "sheets.properties(sheetId,title,index)" },
        headers: { "Authorization" => "Bearer google-access-secret" }
      ).to_return(
        status: 200,
        body: {
          sheets: [
            { properties: { sheetId: 0, title: "Nội dung", index: 0 } },
            { properties: { sheetId: 1, title: "Lịch sử", index: 1 } }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = google_client.spreadsheet_worksheets(spreadsheet_id: "spreadsheet-42")

      expect(result).to eq(
        [
          { "sheetId" => 0, "title" => "Nội dung", "index" => 0 },
          { "sheetId" => 1, "title" => "Lịch sử", "index" => 1 }
        ]
      )
      expect(request).to have_been_requested.once
    end
  end

  describe "#list_drive_folders" do
    let(:google_client) { Google::Client.new(access_token: "google-access-secret") }

    it "returns folders visible to the connected Drive scope" do
      request = stub_request(:get, "https://www.googleapis.com/drive/v3/files")
        .with(
          query: {
            "fields" => "files(id,name,mimeType,webViewLink)",
            "pageSize" => "100",
            "q" => "mimeType = 'application/vnd.google-apps.folder' and trashed = false"
          },
          headers: { "Authorization" => "Bearer google-access-secret" }
        )
        .to_return(
          status: 200,
          body: {
            files: [ { id: "folder-42", name: "AffiHub", mimeType: "application/vnd.google-apps.folder" } ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      result = google_client.list_drive_folders

      expect(result).to eq(
        [ { "id" => "folder-42", "name" => "AffiHub", "mimeType" => "application/vnd.google-apps.folder" } ]
      )
      expect(request).to have_been_requested.once
    end
  end
end
