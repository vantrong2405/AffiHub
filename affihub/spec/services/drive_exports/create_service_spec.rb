require "rails_helper"

RSpec.describe "DriveExports::CreateService", type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:video_project) { create(:video_project) }
    let(:render_version) do
      render_version = create(:render_version, video_project:, status: "ready")
      File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) do |file|
        render_version.file.attach(io: file, filename: "render.mp4", content_type: "video/mp4")
      end
      render_version
    end
    let(:google_connection) { create(:google_connection, integration: "drive", status: "connected") }
    let(:service_class) { DriveExports::CreateService }
    let(:service) do
      service_class.new(
        video_project_id: video_project.id,
        render_version_id: render_version.id,
        google_connection_id: google_connection.id
      )
    end

    it "returns a queued Drive export and enqueues one upload" do
      service.call

      expect(service).to be_success
      expect(service.drive_export.attributes.slice("status", "folder_key", "file_key")).to eq(
        "status" => "queued",
        "folder_key" => "affihub-project-#{video_project.id}",
        "file_key" => "affihub-drive-export-render-#{render_version.id}-connection-#{google_connection.id}"
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end

    it 'returns false and marks the export failed when its upload job cannot be enqueued' do
      allow(DriveExports::UploadJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)

      expect(service.call).to eq(false)

      expect(service.drive_export.reload.attributes.slice("status", "safe_error_code")).to eq(
        "status" => "failed",
        "safe_error_code" => "google_drive_job_enqueue_failed"
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end

    it "does not enqueue a duplicate while the export is already queued" do
      service.call
      service.call

      expect(DriveExport.count).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end

    context "when quota was exhausted on a previous attempt" do
      let!(:drive_export) do
        create(
          :drive_export,
          google_connection:,
          render_version:,
          status: "waiting_for_quota"
        )
      end

      it "returns the export to queued and enqueues one user-requested retry" do
        service.call

        expect(service).to be_success
        expect(drive_export.reload.status).to eq("queued")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
      end
    end

    context "when the previous upload outcome is unknown" do
      let!(:drive_export) do
        create(
          :drive_export,
          google_connection:,
          render_version:,
          status: "outcome_unknown"
        )
      end

      it "returns the unresolved export without enqueueing another upload" do
        service.call

        expect(service).to be_success
        expect(drive_export.reload.status).to eq("outcome_unknown")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
      end
    end
  end
end
