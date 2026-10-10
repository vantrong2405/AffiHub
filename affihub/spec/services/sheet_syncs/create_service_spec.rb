require "rails_helper"

RSpec.describe "SheetSyncs::CreateService", type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:google_connection) do
      create(
        :google_connection,
        integration: "sheets",
        spreadsheet_id: "spreadsheet-42",
        worksheet_title: "Nội dung"
      )
    end
    let(:video_project) { create(:video_project) }
    let(:render_version) { create(:render_version, video_project:) }
    let(:social_destination) { create(:social_destination) }
    let(:service_class) { SheetSyncs::CreateService }
    let(:service) do
      service_class.new(
        google_connection_id: google_connection.id,
        render_version_id: render_version.id,
        social_destination_id: social_destination.id
      )
    end

    it "returns the stable row key and enqueues one isolated SheetSync" do
      expect(service.call).to eq(true)

      expect(service.sheet_sync).to have_attributes(
        sheet_row_key: "affihub-project-#{video_project.id}-render-#{render_version.id}-destination-#{social_destination.id}",
        status: "queued"
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch(:job)).to eq(SheetSyncs::SyncJob)
    end

    it "reuses the same project, render, destination, and connection row" do
      expect(service.call).to eq(true)
      repeated_service = service_class.new(
        google_connection_id: google_connection.id,
        render_version_id: render_version.id,
        social_destination_id: social_destination.id
      )
      expect(repeated_service.call).to eq(true)

      expect(SheetSync.count).to eq(1)
      expect(repeated_service.sheet_sync.id).to eq(service.sheet_sync.id)
    end
  end
end
