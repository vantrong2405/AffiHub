# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkflowRuns::HeartbeatService, type: :service do
  describe "#call" do
    it "returns failure when the worker presents a stale fencing token" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-a", fencing_token: 2, lease_expires_at: 1.minute.from_now)
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 1
      )

      service.call

      expect(service).not_to be_success
      expect(workflow_run.reload.heartbeat_at).to be_nil
    end

    it "returns success and extends the lease for its current owner" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-a", fencing_token: 2, lease_expires_at: 1.minute.from_now)
      service = described_class.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 2
      )

      service.call

      expect(service).to be_success
      expect(workflow_run.reload.lease_expires_at).to be > Time.current
    end
  end
end
