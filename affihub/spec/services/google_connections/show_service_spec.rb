require "rails_helper"

RSpec.describe "GoogleConnections::ShowService", type: :service do
  describe "#call" do
    let(:google_connection) { create(:google_connection, integration: "sheets") }
    let(:spreadsheet_id) { "spreadsheet-42" }
    let(:worksheet) { { "sheetId" => 0, "title" => "Nội dung", "index" => 0 } }
    let(:google_client) { instance_double(Google::Client) }
    let(:access_token_service) do
      instance_double(GoogleConnections::AccessTokenService, call: true, access_token: "google-access-token")
    end
    let(:service_class) { GoogleConnections::ShowService }
    let(:service) do
      service_class.new(google_connection_id: google_connection.id, spreadsheet_id:)
    end

    before do
      allow(GoogleConnections::AccessTokenService).to receive(:new).and_return(access_token_service)
      allow(Google::Client).to receive(:new).and_return(google_client)
      allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id:).and_return([ worksheet ])
    end

    it "returns the tabs for the selected spreadsheet" do
      expect(service.call).to eq(true)
      expect(service.worksheets).to eq([ worksheet ])
      expect(service.has_worksheets).to eq(true)
    end

    context "when Google denies access to the selected spreadsheet" do
      before do
        allow(google_client).to receive(:spreadsheet_worksheets).with(spreadsheet_id:)
          .and_raise(Google::Client::ApiError.new(status: 403, reason: "access_denied"))
      end

      it "returns the settings page with a safe selection error and no worksheets" do
        expect(service.call).to eq(true)
        expect(service.has_option_load_error).to eq(true)
        expect(service.has_worksheets).to eq(false)
        expect(service.worksheets).to eq([])
      end
    end
  end
end
