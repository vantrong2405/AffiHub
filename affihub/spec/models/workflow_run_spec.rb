# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkflowRun, type: :model do
  describe "status" do
    it "returns queued as the configured default" do
      expect(build(:workflow_run).status).to eq("queued")
    end

    it "returns running for an active run" do
      workflow_run = build(:workflow_run, status: "running")

      expect(workflow_run.status).to eq("running")
    end

    it "returns reconciliation required for a run awaiting review" do
      workflow_run = build(:workflow_run, status: "reconciliation_required")

      expect(workflow_run.status).to eq("reconciliation_required")
    end

    it "returns outcome unknown for a run with an unclear result" do
      workflow_run = build(:workflow_run, status: "outcome_unknown")

      expect(workflow_run.status).to eq("outcome_unknown")
    end

    it "returns completed for a successful run" do
      workflow_run = build(:workflow_run, status: "completed")

      expect(workflow_run.status).to eq("completed")
    end

    it "returns failed for a failed run" do
      workflow_run = build(:workflow_run, status: "failed")

      expect(workflow_run.status).to eq("failed")
    end
  end

  describe "associations" do
    it "returns the outbound attempts for the workflow run" do
      workflow_run = create(:workflow_run)
      attempt = create(:outbound_attempt, workflow_run:)

      expect(workflow_run.outbound_attempts.to_a).to eq([ attempt ])
    end

    it "returns the audit events for the workflow run" do
      workflow_run = create(:workflow_run)
      event = create(:workflow_audit_event, workflow_run:)

      expect(workflow_run.workflow_audit_events.to_a).to eq([ event ])
    end
  end
end
