require "rails_helper"

RSpec.describe "OutboundAttempts::StartService", type: :service do
  describe "#call" do
    it "returns one durable submitting attempt for a workflow step" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-1", fencing_token: 3, lease_expires_at: 1.minute.from_now)
      service = "OutboundAttempts::StartService".constantize.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      service.call

      expect(service).to be_success
      expect(service.outbound_attempt.status).to eq("submitting")
      expect(workflow_run.outbound_attempts.sole.attempt_id).to eq(service.outbound_attempt.attempt_id)
    end

    it "returns the existing unresolved attempt without creating a second one" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-1", fencing_token: 3, lease_expires_at: 1.minute.from_now)
      attempt = create(:outbound_attempt, workflow_run:, status: "submitting")
      service = "OutboundAttempts::StartService".constantize.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-1",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      expect { service.call }.not_to change { workflow_run.outbound_attempts.count }
      expect(service.outbound_attempt).to eq(attempt)
    end

    it "returns failure when a worker has lost its fencing token" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-b", fencing_token: 4, lease_expires_at: 1.minute.from_now)
      service = "OutboundAttempts::StartService".constantize.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 3,
        stage: "publish",
        request_timeout_at: 1.minute.from_now
      )

      service.call

      expect(service).not_to be_success
      expect(workflow_run.outbound_attempts).to be_empty
    end
  end
end
