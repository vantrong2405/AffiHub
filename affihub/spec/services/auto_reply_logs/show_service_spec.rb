require "rails_helper"

RSpec.describe AutoReplyLogs::ShowService, type: :service do
  describe "#call" do
    it "returns the event workflow and append-only audit history" do
      event = create(:auto_reply_event)
      workflow_run = create(
        :workflow_run,
        workflowable: event,
        operation: "auto_reply",
        stage: "reply"
      )
      audit_event = create(
        :workflow_audit_event,
        workflow_run:,
        event_type: "auto_reply_comment_received",
        details: { source: event.source, provider_comment_id: event.provider_comment_id }
      )
      service = described_class.new(event_id: event.id)

      expect(service.call).to eq(true)
      expect(service.event).to eq(event)
      expect(service.workflow_run).to eq(workflow_run)
      expect(service.audit_events).to eq([ audit_event ])
    end

    it "returns the latest reply attempt for outcome reconciliation" do
      event = create(:auto_reply_event, status: "outcome_unknown")
      workflow_run = create(
        :workflow_run,
        workflowable: event,
        operation: "auto_reply",
        stage: "reply",
        status: "outcome_unknown"
      )
      earlier_attempt = create(
        :outbound_attempt,
        workflow_run:,
        stage: "reply",
        status: "failed",
        attempt_number: 1
      )
      latest_attempt = create(
        :outbound_attempt,
        workflow_run:,
        stage: "reply",
        status: "outcome_unknown",
        attempt_number: 2
      )
      service = described_class.new(event_id: event.id)

      expect(service.call).to eq(true)

      expect(service.outbound_attempt).to eq(latest_attempt)
      expect(service.outbound_attempt).not_to eq(earlier_attempt)
    end

    it "returns failure when the event does not exist" do
      service = described_class.new(event_id: -1)

      expect(service.call).to eq(false)
    end
  end
end
