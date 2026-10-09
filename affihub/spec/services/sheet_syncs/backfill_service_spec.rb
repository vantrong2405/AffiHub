require "rails_helper"

RSpec.describe "SheetSyncs::BackfillService", type: :service do
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
    let(:selected_render_version) { create(:render_version, video_project:) }
    let(:unselected_render_version) { create(:render_version, video_project:) }
    let(:social_destination) { create(:social_destination) }
    let(:service_class) { SheetSyncs::BackfillService }
    let(:service) do
      service_class.new(
        google_connection_id: google_connection.id,
        video_project_id: video_project.id,
        render_version_ids: [ selected_render_version.id ]
      )
    end

    before do
      create(:publication, render_version: selected_render_version, social_destination:)
      create(:publication, render_version: unselected_render_version, social_destination:)
    end

    it "queues only the explicitly selected render and leaves the rest of the library untouched" do
      expect(service.call).to eq(true)

      expect(SheetSync.pluck(:render_version_id)).to eq([ selected_render_version.id ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end
  end
end
