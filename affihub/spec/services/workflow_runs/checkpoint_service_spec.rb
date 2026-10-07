require "rails_helper"

RSpec.describe "WorkflowRuns::CheckpointService", type: :service do
  describe "#call" do
    it "returns the checkpoint only for the worker holding the current fencing token" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-a", fencing_token: 4, lease_expires_at: 1.minute.from_now)
      service = "WorkflowRuns::CheckpointService".constantize.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 4,
        stage: "uploading",
        checkpoint: { offset: 1_048_576 }
      )

      service.call

      expect(service).to be_success
      expect(workflow_run.reload.checkpoint).to eq("offset" => 1_048_576)
    end

    it "returns failure and leaves the last checkpoint unchanged for a stale worker" do
      workflow_run = create(:workflow_run, status: "running", worker_id: "worker-b", fencing_token: 5, lease_expires_at: 1.minute.from_now, checkpoint: { offset: 10 })
      service = "WorkflowRuns::CheckpointService".constantize.new(
        workflow_run_id: workflow_run.id,
        worker_id: "worker-a",
        fencing_token: 4,
        stage: "uploading",
        checkpoint: { offset: 20 }
      )

      service.call

      expect(service).not_to be_success
      expect(workflow_run.reload.checkpoint).to eq("offset" => 10)
    end
  end
end
