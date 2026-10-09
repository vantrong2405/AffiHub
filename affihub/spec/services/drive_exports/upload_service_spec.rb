require "rails_helper"

RSpec.describe "DriveExports::UploadService", type: :service do
  describe "#call" do
    let(:google_connection) { create(:google_connection, integration: "drive") }
    let(:video_project) { create(:video_project) }
    let(:render_version) do
      render_version = create(:render_version, video_project:, status: "ready")
      File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) do |file|
        render_version.file.attach(io: file, filename: "render.mp4", content_type: "video/mp4")
      end
      render_version
    end
    let(:second_render_version) do
      render_version = create(:render_version, video_project:, status: "ready")
      File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) do |file|
        render_version.file.attach(io: file, filename: "second-render.mp4", content_type: "video/mp4")
      end
      render_version
    end
    let(:drive_export) do
      create(
        :drive_export,
        google_connection:,
        render_version:,
        status: "queued"
      )
    end
    let(:second_drive_export) do
      create(
        :drive_export,
        google_connection:,
        render_version: second_render_version,
        status: "queued"
      )
    end
    let(:google_client) { instance_double(Google::Client) }
    let(:service_class) { DriveExports::UploadService }
    let(:service) { service_class.new(drive_export_id: drive_export.id) }
    let(:second_service) { service_class.new(drive_export_id: second_drive_export.id) }
    let(:folder_keys) { [] }
    let(:file_keys) { [] }
    let(:folder) { { "id" => "drive-folder-1", "webViewLink" => "https://drive.google.com/drive/folders/folder-1" } }
    let(:file) { { "id" => "drive-file-1", "webViewLink" => "https://drive.google.com/file/d/file-1" } }
    let(:upload_session_uri) do
      "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=private-session"
    end

    before do
      allow(Google::Client).to receive(:new).and_return(google_client)
      allow(google_client).to receive(:create_upload_session).and_return(upload_session_uri)
      allow(google_client).to receive(:upload_file).and_return(file)
      allow(google_client).to receive(:find_folder) do |folder_key:|
        folder_keys << folder_key
        folder
      end
      allow(google_client).to receive(:find_file) do |file_key:|
        file_keys << file_key
        file
      end
    end

    it "returns a stable folder key per project and a distinct file key per render export" do
      service.call
      second_service.call

      expect(service).to be_success
      expect(second_service).to be_success
      expect(folder_keys.length).to eq(2)
      expect(folder_keys.uniq).to eq([ folder_keys.first ])
      expect(file_keys.length).to eq(2)
      expect(file_keys.uniq.length).to eq(2)
      expect(drive_export.reload).to have_attributes(
        status: "succeeded",
        drive_folder_id: "drive-folder-1",
        drive_file_id: "drive-file-1"
      )
    end

    it "returns a private inherited folder without assigning explicit public permissions" do
      allow(google_client).to receive(:find_folder) do |folder_key:|
        folder_keys << folder_key
        nil
      end
      allow(google_client).to receive(:create_folder).and_return(folder)
      allow(google_client).to receive(:find_file) do |file_key:|
        file_keys << file_key
        nil
      end
      allow(google_client).to receive(:upload_file).and_return(file)

      service.call

      expect(google_client).to have_received(:create_folder).with(
        folder_key: folder_keys.sole,
        name: video_project.name,
        parent_id: nil
      )
      expect(google_client).to have_received(:create_upload_session).with(
        folder_id: "drive-folder-1",
        file_key: file_keys.sole,
        file_name: "render-#{file_keys.sole}.mp4",
        file_size: render_version.file.byte_size
      )
      expect(google_client).to have_received(:upload_file).once
    end

    it "returns a completed Drive export and queues a Sheets refresh for its current publication row" do
      sheets_connection = create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung"
      )
      social_destination = create(:social_destination)
      create(:publication, render_version:, social_destination:, status: "draft")
      sheet_sync = create(
        :sheet_sync,
        google_connection: sheets_connection,
        render_version:,
        social_destination:,
        status: "succeeded"
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect(service.call).to eq(true)

      expect(drive_export.reload.status).to eq("succeeded")
      expect(sheet_sync.reload.status).to eq("queued")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch(:job)).to eq(SheetSyncs::SyncJob)
    end

    context "when the standard Google API quota is exhausted" do
      before do
        allow(google_client).to receive(:find_folder).and_return(nil)
        allow(google_client).to receive(:create_folder).and_raise(
          Google::Client::DailyQuotaExceeded.new(status: 403, reason: "dailyLimitExceeded")
        )
      end

      it "returns a Drive export waiting for quota without attempting the file upload" do
        service.call

        expect(service).not_to be_success
        expect(drive_export.reload.status).to eq("waiting_for_quota")
        expect(google_client).not_to have_received(:upload_file)
      end
    end

    context "when the Google account storage is full" do
      let(:publication) { create(:publication, render_version:, status: "approved") }

      before do
        publication
        allow(google_client).to receive(:find_folder).and_return(folder)
        allow(google_client).to receive(:find_file).and_return(nil)
        allow(google_client).to receive(:upload_file).and_raise(
          Google::Client::StorageQuotaExceeded.new(status: 403, reason: "storageQuotaExceeded")
        )
      end

      it "returns a storage-full status without retrying or changing the local publication" do
        service.call

        expect(service).not_to be_success
        expect(drive_export.reload.status).to eq("storage_quota_exceeded")
        expect(google_client).to have_received(:upload_file).once
        expect(publication.reload.status).to eq("approved")
      end
    end

    context "when Google returns a temporary rate limit" do
      before do
        allow(google_client).to receive(:find_folder).and_return(folder)
        allow(google_client).to receive(:find_file).and_return(nil)
        allow(google_client).to receive(:upload_file).and_raise(
          Google::Client::RateLimitError.new(status: 429, reason: "rateLimitExceeded")
        )
      end

      it "raises the rate limit after marking the export for bounded retry" do
        expect do
          service.call
        end.to raise_error(Google::Client::RateLimitError)

        expect(drive_export.reload.status).to eq("retrying")
        expect(google_client).to have_received(:upload_file).once
      end
    end

    context "when the upload request times out" do
      before do
        find_file_calls = 0
        allow(google_client).to receive(:find_file) do |file_key:|
          file_keys << file_key
          find_file_calls += 1
          find_file_calls == 1 ? nil : file
        end
        allow(google_client).to receive(:upload_file).and_raise(Timeout::Error)
      end

      it "returns the reconciled file without creating a duplicate" do
        service.call

        expect(service).to be_success
        expect(google_client).to have_received(:upload_file).once
        expect(google_client).to have_received(:find_file).twice
        expect(drive_export.reload).to have_attributes(status: "succeeded", drive_file_id: "drive-file-1")
      end
    end

    context "when reconciliation cannot determine whether the upload completed" do
      before do
        find_file_calls = 0
        allow(google_client).to receive(:find_file) do |file_key:|
          file_keys << file_key
          find_file_calls += 1
          raise Timeout::Error if find_file_calls == 2

          nil
        end
        allow(google_client).to receive(:upload_file).and_raise(Timeout::Error)
      end

      it "returns OutcomeUnknown and does not retry the upload" do
        service.call

        expect(service).not_to be_success
        expect(drive_export.reload.status).to eq("outcome_unknown")
        expect(google_client).to have_received(:upload_file).once
        expect(drive_export.read_attribute_before_type_cast(:upload_session_uri)).not_to match(
          Regexp.escape(upload_session_uri)
        )
        expect(service.errors.full_messages.to_sentence).not_to match(Regexp.escape(upload_session_uri))
      end
    end
  end
end
