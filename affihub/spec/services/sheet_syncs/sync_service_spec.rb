require "rails_helper"

RSpec.describe "SheetSyncs::SyncService", type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project, name: "Chiến dịch mùa thu") }
    let(:render_version) { create(:render_version, video_project:) }
    let(:social_destination) { create(:social_destination, name: "Trang AffiHub") }
    let(:google_connection) do
      create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung"
      )
    end
    let(:older_publication) do
      create(:publication, render_version:, social_destination:, caption: "Bản cũ", status: "failed")
    end
    let(:latest_publication) do
      create(
        :publication,
        render_version:,
        social_destination:,
        caption: "Caption mới nhất",
        status: "published",
        platform_post_id: "post-42",
        permalink: "https://example.test/posts/42",
        published_at: Time.zone.parse("2026-10-08 09:30:00")
      )
    end
    let(:drive_connection) { create(:google_connection, integration: "drive") }
    let!(:drive_export) do
      create(
        :drive_export,
        google_connection: drive_connection,
        render_version:,
        status: "succeeded",
        drive_url: "https://drive.google.com/file/d/render-42"
      )
    end
    let(:sheet_sync) do
      create(
        :sheet_sync,
        google_connection:,
        render_version:,
        social_destination:,
        status: "queued"
      )
    end
    let(:google_client) { instance_double(Google::Client) }
    let(:upserted_rows) { [] }
    let(:access_token_service) { instance_double(GoogleConnections::AccessTokenService, call: true, access_token: "access-token") }
    let(:service_class) { SheetSyncs::SyncService }
    let(:service) { service_class.new(sheet_sync_id: sheet_sync.id) }

    before do
      older_publication
      latest_publication
      allow(GoogleConnections::AccessTokenService).to receive(:new).and_return(access_token_service)
      allow(Google::Client).to receive(:new).and_return(google_client)
      allow(google_client).to receive(:upsert_sheet_row) do |**arguments|
        upserted_rows << arguments
        8
      end
    end

    it "returns a serialized RAW upsert of the latest occurrence into one current row" do
      expect(service.call).to eq(true)

      expect(upserted_rows.length).to eq(1)
      expect(upserted_rows.last).to eq(
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung",
        row_key: "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
        values: [
          "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
          "Chiến dịch mùa thu",
          render_version.id.to_s,
          "facebook",
          "Trang AffiHub",
          "Caption mới nhất",
          "https://drive.google.com/file/d/render-42",
          "published",
          "post-42",
          "https://example.test/posts/42",
          "2026-10-08T09:30:00Z",
          "",
          latest_publication.updated_at.iso8601
        ]
      )
      expect(sheet_sync.reload).to have_attributes(status: "succeeded", row_number: 8)
      expect(Publication.count).to eq(2)
      expect(older_publication.reload.status).to eq("failed")
    end

    it "sends a row without a Drive link when Drive has not completed" do
      drive_export.destroy!
      expect(service.call).to eq(true)

      expect(upserted_rows.length).to eq(1)
      expect(upserted_rows.last).to eq(
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung",
        row_key: "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
        values: [
          "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
          "Chiến dịch mùa thu",
          render_version.id.to_s,
          "facebook",
          "Trang AffiHub",
          "Caption mới nhất",
          "",
          "published",
          "post-42",
          "https://example.test/posts/42",
          "2026-10-08T09:30:00Z",
          "",
          latest_publication.updated_at.iso8601
        ]
      )
    end

    it "returns the same row updated with the latest recurring Publication occurrence" do
      expect(service.call).to eq(true)
      new_publication = create(
        :publication,
        render_version:,
        social_destination:,
        caption: "Caption của occurrence mới",
        status: "published",
        platform_post_id: "post-43",
        permalink: "https://example.test/posts/43",
        published_at: Time.zone.parse("2026-10-09 10:00:00")
      )
      second_sync = SheetSyncs::SyncService.new(sheet_sync_id: sheet_sync.id)

      expect(SheetSync.count).to eq(1)
      expect(sheet_sync.reload.status).to eq("queued")
      expect(second_sync.call).to eq(true)

      expect(upserted_rows.length).to eq(2)
      expect(upserted_rows.last).to eq(
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung",
        row_key: "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
        values: [
          "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
          "Chiến dịch mùa thu",
          render_version.id.to_s,
          "facebook",
          "Trang AffiHub",
          "Caption của occurrence mới",
          "https://drive.google.com/file/d/render-42",
          "published",
          "post-43",
          "https://example.test/posts/43",
          "2026-10-09T10:00:00Z",
          "",
          new_publication.updated_at.iso8601
        ]
      )
      expect(Publication.count).to eq(3)
      expect(older_publication.reload.status).to eq("failed")
      expect(latest_publication.reload.platform_post_id).to eq("post-42")
    end

    it "returns OutcomeUnknown for a Sheets timeout without changing Drive or Publication" do
      allow(google_client).to receive(:upsert_sheet_row).and_raise(
        Google::Client::NetworkError.new(status: nil, reason: "network_request_failed")
      )
      expect(Publications::PublishJob).not_to receive(:perform_later)

      expect do
        service.call
      end.to raise_error(Google::Client::NetworkError)

      expect(sheet_sync.reload.status).to eq("outcome_unknown")
      expect(drive_export.reload.status).to eq("succeeded")
      expect(latest_publication.reload.status).to eq("published")
    end

    it "returns waiting for standard free quota without changing Drive or Publication" do
      allow(google_client).to receive(:upsert_sheet_row).and_raise(
        Google::Client::DailyQuotaExceeded.new(status: 403, reason: "quotaExceeded")
      )

      expect(service.call).to eq(false)

      expect(sheet_sync.reload.status).to eq("waiting_for_quota")
      expect(sheet_sync.safe_error_code).to eq("google_sheets_daily_quota_exhausted")
      expect(drive_export.reload.status).to eq("succeeded")
      expect(latest_publication.reload.status).to eq("published")
    end
  end
end
