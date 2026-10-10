require "rails_helper"

RSpec.describe "SheetSyncs::SyncJob", type: :job do
  describe "#perform" do
    let(:sheet_sync) { create(:sheet_sync) }
    let(:sync_service) { instance_double(SheetSyncs::SyncService) }
    let(:publish_job) { Publications::PublishJob }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      allow(SheetSyncs::SyncService).to receive(:new).and_return(sync_service)
      allow(sync_service).to receive(:call).and_return(true)
    end

    it "returns after running only the SheetSync service" do
      expect(publish_job).not_to receive(:perform_later)
      SheetSyncs::SyncJob.perform_now(sheet_sync.id)

      expect(sync_service).to have_received(:call).once
    end

    it "returns a bounded retry by enqueueing one next SheetSync after a transient Google rate limit" do
      expect(publish_job).not_to receive(:perform_later)
      allow(sync_service).to receive(:call).and_raise(
        Google::Client::RateLimitError.new(status: 429, reason: "rateLimitExceeded")
      )

      SheetSyncs::SyncJob.perform_now(sheet_sync.id)

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch(:job)).to eq(SheetSyncs::SyncJob)
      expect(sync_service).to have_received(:call).once
    end
  end
end
