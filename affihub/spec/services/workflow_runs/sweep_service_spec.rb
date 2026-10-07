# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkflowRuns::SweepService, type: :service do
  describe "#call" do
    it "requeues a stale run and records lease expiration when no outbound attempt exists" do
      workflow_run = create(:workflow_run, status: "running", lease_expires_at: 1.minute.ago, worker_id: "worker-a")
      service = described_class.new

      service.call

      expect(workflow_run.reload.status).to eq("queued")
      expect(workflow_run.workflow_audit_events.sole.event_type).to eq("lease_expired")
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
