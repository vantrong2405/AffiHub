# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundAttempt, type: :model do
  describe "status" do
    it "returns prepared as the configured default" do
      expect(build(:outbound_attempt).status).to eq("prepared")
    end

    it "returns submitting while a request is in flight" do
      outbound_attempt = build(:outbound_attempt, status: "submitting")

      expect(outbound_attempt.status).to eq("submitting")
    end

    it "returns confirmed after the provider confirms the request" do
      outbound_attempt = build(:outbound_attempt, status: "confirmed")

      expect(outbound_attempt.status).to eq("confirmed")
    end

    it "returns failed after a confirmed provider failure" do
      outbound_attempt = build(:outbound_attempt, status: "failed")

      expect(outbound_attempt.status).to eq("failed")
    end

    it "returns outcome unknown while the provider result is unclear" do
      outbound_attempt = build(:outbound_attempt, status: "outcome_unknown")

      expect(outbound_attempt.status).to eq("outcome_unknown")
    end

    it "returns manual outcome confirmed after a user confirms the result" do
      outbound_attempt = build(:outbound_attempt, status: "manual_outcome_confirmed")

      expect(outbound_attempt.status).to eq("manual_outcome_confirmed")
    end

    it "returns manual outcome not occurred after a user confirms no side effect" do
      outbound_attempt = build(:outbound_attempt, status: "manual_outcome_not_occurred")

      expect(outbound_attempt.status).to eq("manual_outcome_not_occurred")
    end
  end

  describe "references" do
    it "returns the workflow run that owns the attempt" do
      workflow_run = build(:workflow_run)
      attempt = build(:outbound_attempt, workflow_run:)

      expect(attempt.workflow_run).to eq(workflow_run)
    end
  end
end
