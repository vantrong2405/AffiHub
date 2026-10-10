require "rails_helper"

RSpec.describe WorkflowRuns::SweepJob, type: :job do
  after do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe "#perform" do
    it "enqueues recovery for a workflow whose lease expired" do
      drive_export = create(:drive_export, status: "uploading")
      create(
        :workflow_run,
        workflowable: drive_export,
        operation: "drive_export_upload",
        stage: "upload",
        status: "running",
        worker_id: "drive-worker-old",
        lease_expires_at: 1.minute.ago
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ DriveExports::UploadJob ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.sole.fetch(:args)).to eq([ drive_export.id ])
    end
  end
end
