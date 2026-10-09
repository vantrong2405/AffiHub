require "rails_helper"

RSpec.describe "GoogleConnections::UpdateService", type: :service do
  describe "#call" do
    let(:google_connection) { create(:google_connection, integration: "sheets") }
    let(:google_client) { instance_double(Google::Client) }
    let(:access_token_service) do
      instance_double(GoogleConnections::AccessTokenService, call: true, access_token: "google-access-token")
    end
    let(:attributes) do
      {
        "spreadsheet_id" => "spreadsheet-42",
        "worksheet_title" => "Nội dung"
      }
    end
    let(:service_class) { GoogleConnections::UpdateService }
    let(:service) { service_class.new(google_connection_id: google_connection.id, attributes:) }

    before do
      allow(GoogleConnections::AccessTokenService).to receive(:new).and_return(access_token_service)
      allow(Google::Client).to receive(:new).and_return(google_client)
    end

    context "when the selected Google Sheets tab is accessible" do
      before do
        allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id: "spreadsheet-42")
          .and_return([ { "sheetId" => 0, "title" => "Nội dung" } ])
      end

      it "returns the saved spreadsheet ID and selected tab" do
        expect(service.call).to eq(true)

        expect(google_connection.reload).to have_attributes(
          spreadsheet_id: "spreadsheet-42",
          worksheet_title: "Nội dung"
        )
      end
    end

    context "when the selected tab is not in the accessible spreadsheet" do
      before do
        allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id: "spreadsheet-42")
          .and_return([ { "sheetId" => 0, "title" => "Lịch sử" } ])
      end

      it "returns failure and leaves the stored spreadsheet settings unchanged" do
        expect(service.call).to eq(false)

        expect(google_connection.reload).to have_attributes(spreadsheet_id: nil, worksheet_title: nil)
      end
    end

    context "when Google cannot access the selected spreadsheet" do
      let(:google_connection) do
        create(:google_connection, integration: "sheets", spreadsheet_id: "spreadsheet-old", worksheet_title: "Cũ")
      end

      before do
        allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id: "spreadsheet-42")
          .and_raise(Google::Client::ApiError.new(status: 403, reason: "access_denied"))
      end

      it "returns failure and preserves the saved spreadsheet when access is denied" do
        expect(service.call).to eq(false)

        expect(google_connection.reload.attributes.slice("spreadsheet_id", "worksheet_title")).to eq(
          "spreadsheet_id" => "spreadsheet-old",
          "worksheet_title" => "Cũ"
        )
      end
    end

    context "when the selected ID does not resolve to a Google Spreadsheet" do
      let(:google_connection) do
        create(:google_connection, integration: "sheets", spreadsheet_id: "spreadsheet-old", worksheet_title: "Cũ")
      end

      before do
        allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id: "spreadsheet-42")
          .and_raise(Google::Client::ApiError.new(status: 404, reason: "not_found"))
      end

      it "returns failure and preserves the saved spreadsheet when the file is not a Google Sheet" do
        expect(service.call).to eq(false)

        expect(google_connection.reload.attributes.slice("spreadsheet_id", "worksheet_title")).to eq(
          "spreadsheet_id" => "spreadsheet-old",
          "worksheet_title" => "Cũ"
        )
      end
    end

    context "when the submitted selection is a URL instead of a Picker spreadsheet ID" do
      let(:attributes) do
        {
          "spreadsheet_id" => "https://docs.google.com/spreadsheets/d/spreadsheet-42/edit",
          "worksheet_title" => "Nội dung"
        }
      end

      it "returns failure without changing the saved spreadsheet" do
        expect(service.call).to eq(false)

        expect(google_connection.reload.attributes.slice("spreadsheet_id", "worksheet_title")).to eq(
          "spreadsheet_id" => nil,
          "worksheet_title" => nil
        )
      end
    end

    context "when the user selects a Drive folder visible to the app" do
      let(:google_connection) { create(:google_connection, integration: "drive") }
      let(:attributes) { { "drive_parent_folder_id" => "folder-42" } }

      before do
        allow(google_client).to receive(:find_drive_folder).with(folder_id: "folder-42")
          .and_return(
            "id" => "folder-42",
            "name" => "Video AffiHub",
            "mimeType" => "application/vnd.google-apps.folder"
          )
      end

      it "returns the saved parent folder ID" do
        expect(service.call).to eq(true)

        expect(google_connection.reload.drive_parent_folder_id).to eq("folder-42")
      end
    end
  end
end
