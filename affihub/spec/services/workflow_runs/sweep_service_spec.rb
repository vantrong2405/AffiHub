# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkflowRuns::SweepService, type: :service do
  describe "#call" do
    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    after do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "requeues a stale run and records lease expiration when no outbound attempt exists" do
      workflow_run = create(:workflow_run, status: "running", lease_expires_at: 1.minute.ago, worker_id: "worker-a")
      service = described_class.new

      service.call

      expect(workflow_run.reload.status).to eq("queued")
      expect(workflow_run.workflow_audit_events.sole.event_type).to eq("lease_expired")
    end

    it "enqueues a Drive upload after recovering an expired upload lease" do
      drive_export = create(:drive_export, status: "uploading")
      workflow_run = create(
        :workflow_run,
        workflowable: drive_export,
        operation: "drive_export_upload",
        stage: "upload",
        status: "running",
        worker_id: "drive-worker-old",
        lease_expires_at: 1.minute.ago
      )

      expect(described_class.new.call).to eq(true)

      expect(workflow_run.reload.status).to eq("queued")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ DriveExports::UploadJob ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.sole.fetch(:args)).to eq([ drive_export.id ])
    end

    it "returns failure then enqueues pending recovery on the next sweep after enqueue rejection" do
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
      allow(DriveExports::UploadJob).to receive(:perform_later).and_return(nil)

      expect(described_class.new.call).to eq(false)
      expect(WorkflowRuns::RecoveryDispatch.count).to eq(1)

      allow(DriveExports::UploadJob).to receive(:perform_later).and_call_original

      expect(described_class.new.call).to eq(true)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ DriveExports::UploadJob ])
      expect(WorkflowRuns::RecoveryDispatch.count).to eq(0)
    end

    it "enqueues publication reconciliation without creating another outbound attempt" do
      publication = create(:publication, status: "uploading")
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "running",
        worker_id: "publication-worker-old",
        lease_expires_at: 1.minute.ago
      )
      create(:outbound_attempt, workflow_run:, status: "submitting")

      expect(described_class.new.call).to eq(true)

      expect(workflow_run.reload.status).to eq("reconciliation_required")
      expect(workflow_run.outbound_attempts.count).to eq(1)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ Publications::PublishJob ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.sole.fetch(:args)).to eq([ workflow_run.id ])
    end

    it "enqueues saved MPT submission reconciliation without submitting again" do
      ai_generation = create(:ai_generation, status: "outcome_unknown")
      workflow_run = create(
        :workflow_run,
        workflowable: ai_generation,
        operation: "ai_video_generation",
        stage: "mpt_video_submission",
        status: "running",
        worker_id: "mpt-worker-old",
        lease_expires_at: 1.minute.ago
      )
      create(:outbound_attempt, workflow_run:, stage: "mpt_video_submission", status: "submitting")

      expect(described_class.new.call).to eq(true)

      expect(workflow_run.reload.status).to eq("reconciliation_required")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ AiGenerations::ReconcileJob ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.sole.fetch(:args)).to eq([ ai_generation.id ])
    end

    it "enqueues a queued auto-reply after recovering its lease when no reply attempt exists" do
      auto_reply_event = create(:auto_reply_event)
      workflow_run = create(
        :workflow_run,
        workflowable: auto_reply_event,
        operation: "auto_reply",
        stage: "reply",
        status: "running",
        worker_id: "reply-worker-old",
        lease_expires_at: 1.minute.ago
      )

      expect(described_class.new.call).to eq(true)

      expect(workflow_run.reload.status).to eq("queued")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ AutoResponder::ProcessJob ])
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.sole.fetch(:args)).to eq([ workflow_run.id ])
    end

    it "does not enqueue an auto-reply again while its previous send is unresolved" do
      auto_reply_event = create(:auto_reply_event)
      workflow_run = create(
        :workflow_run,
        workflowable: auto_reply_event,
        operation: "auto_reply",
        stage: "reply",
        status: "running",
        worker_id: "reply-worker-old",
        lease_expires_at: 1.minute.ago
      )
      create(:outbound_attempt, workflow_run:, stage: "reply", status: "submitting")

      expect(described_class.new.call).to eq(true)

      expect(workflow_run.reload.status).to eq("reconciliation_required")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end

    it "reconciles an unresolved attempt without creating a second attempt" do
      workflow_run = create(:workflow_run, status: "running", lease_expires_at: 1.minute.ago)
      create(:outbound_attempt, workflow_run:, status: "submitting")
      service = described_class.new

      expect { service.call }.not_to change { workflow_run.outbound_attempts.count }
      expect(workflow_run.reload.status).to eq("reconciliation_required")
    end
  end
end
