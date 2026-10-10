require "rails_helper"

RSpec.describe DriveExports::UploadJob, type: :job do
  describe "#perform" do
    let(:drive_export_id) { 42 }
    let(:upload_service) { instance_double(DriveExports::UploadService) }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      allow(DriveExports::UploadService).to receive(:new).with(drive_export_id:).and_return(upload_service)
      allow(upload_service).to receive(:call).and_raise(
        Google::Client::RateLimitError.new(status: 429, reason: "rateLimitExceeded")
      )
    end

    it "re-enqueues a temporary rate limit with an exponential delay" do
      started_at = Time.current
      described_class.perform_now(drive_export_id)

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)

      retry_job = ActiveJob::Base.queue_adapter.enqueued_jobs.sole
      wait_seconds = Rails.application.config_for(:google).deep_symbolize_keys
        .fetch(:rate_limit).fetch(:initial_wait_seconds)

      expect(retry_job.fetch(:at)).to be_between(
        (started_at + wait_seconds).to_f,
        (Time.current + wait_seconds).to_f
      ).inclusive
    end

    it "stops retrying after the configured attempt limit" do
      drive_export = create(:drive_export, status: "retrying")
      workflow_run = create(
        :workflow_run,
        workflowable: drive_export,
        operation: "drive_export_upload",
        stage: "upload",
        status: "queued"
      )
      allow(DriveExports::UploadService).to receive(:new)
        .with(drive_export_id: drive_export.id).and_return(upload_service)
      job = described_class.new(drive_export.id)
      job.perform_now
      job.perform_now
      job.perform_now
      job.perform_now

      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(3)
      expect(upload_service).to have_received(:call).exactly(4).times
      expect(drive_export.reload.status).to eq("failed")
      expect(workflow_run.reload.status).to eq("failed")
      expect(workflow_run.workflow_audit_events.sole.details).to eq(
        "safe_error_code" => "google_drive_rate_limit_retries_exhausted"
      )
    end
  end

  describe ".rate_limit_retry_delay" do
    it "caps exponential delay at the configured maximum" do
      expect(described_class.rate_limit_retry_delay(10)).to eq(60)
    end
  end
end
