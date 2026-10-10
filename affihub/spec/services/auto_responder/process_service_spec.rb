require "rails_helper"

RSpec.describe AutoResponder::ProcessService, type: :service do
  describe "#call" do
    let(:destination) { create(:social_destination, provider: "facebook") }
    let(:rule) do
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
    end
    let(:event) do
      create(:auto_reply_event,
        social_destination: destination,
        source: "facebook",
        event_type: "comment",
        provider_comment_id: "fb-comment-100",
        comment_text: "Mẫu này còn hàng không?",
        status: "queued"
      )
    end
    let(:workflow_run) do
      create(:workflow_run,
        workflowable: event,
        operation_id: "auto-reply-#{SecureRandom.uuid}",
        operation: "auto_reply",
        stage: "reply",
        status: "queued"
      )
    end
    let(:client) { double("Meta::Client") }
    let(:service) do
      described_class.new(workflow_run_id: workflow_run.id, worker_id: "auto-reply-worker-1", client:)
    end

    it "returns without claiming a comment when auto-reply is paused" do
      rule
      workflow_run
      AutomationControl.current.update!(auto_responder_paused: true)
      expect(WorkflowRuns::ClaimService).not_to receive(:new)
      expect(client).not_to receive(:reply_to_comment)

      expect(service.call).to eq(false)

      expect(workflow_run.reload.status).to eq("queued")
      expect(event.reload.status).to eq("queued")
    end

    it "returns a failed result when the default rule is disabled before processing" do
      rule.update!(enabled: false)
      workflow_run
      expect(client).not_to receive(:reply_to_comment)

      expect(service.call).to eq(false)

      expect(event.reload.status).to eq("failed")
      expect(event.safe_error_code).to eq("auto_reply_default_rule_missing")
      expect(workflow_run.reload.status).to eq("failed")
      expect(workflow_run.worker_id).to be_nil
      expect(workflow_run.outbound_attempts).to be_empty
      expect(workflow_run.workflow_audit_events.order(:created_at).last.details).to eq(
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id,
        "rule_snapshot" => nil,
        "reply_text" => nil,
        "provider_reply_id" => nil,
        "status" => "failed",
        "safe_error_code" => "auto_reply_default_rule_missing",
        "manual_evidence" => nil
      )
    end

    it "returns a failed result when the destination is disconnected before processing" do
      rule
      workflow_run
      destination.update!(status: :revoked)
      expect(client).not_to receive(:reply_to_comment)

      expect(service.call).to eq(false)

      expect(event.reload.status).to eq("failed")
      expect(event.safe_error_code).to eq("auto_reply_comment_destination_missing")
      expect(workflow_run.reload.status).to eq("failed")
      expect(workflow_run.outbound_attempts).to be_empty
    end

    it "returns an unknown result after a reply request times out and does not send a second reply" do
      rule
      workflow_run
      allow(client).to receive(:reply_to_comment).and_raise(Net::ReadTimeout)

      expect(service.call).to eq(false)
      expect(event.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("outcome_unknown")
      expect(workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
      expect(workflow_run.workflow_audit_events.order(:created_at).last.details).to eq(
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id,
        "rule_snapshot" => {
          "id" => rule.id,
          "rule_type" => "default",
          "keyword" => nil,
          "reply_text" => "Cảm ơn bạn đã quan tâm."
        },
        "reply_text" => "Cảm ơn bạn đã quan tâm.",
        "provider_reply_id" => nil,
        "status" => "outcome_unknown",
        "safe_error_code" => "network_request_failed",
        "manual_evidence" => nil
      )

      retry_service = described_class.new(workflow_run_id: workflow_run.id, worker_id: "auto-reply-worker-2", client:)
      expect(retry_service.call).to eq(false)
      expect(client).to have_received(:reply_to_comment).once
    end

    it "persists the selected rule and reply in an append-only audit event after success" do
      selected_rule = rule
      workflow_run
      allow(client).to receive(:reply_to_comment).and_return("id" => "fb-reply-200")

      expect(service.call).to eq(true)

      audit_event = workflow_run.workflow_audit_events.order(:created_at).last
      expected_details = {
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id,
        "rule_snapshot" => {
          "id" => selected_rule.id,
          "rule_type" => "default",
          "keyword" => nil,
          "reply_text" => "Cảm ơn bạn đã quan tâm."
        },
        "reply_text" => "Cảm ơn bạn đã quan tâm.",
        "provider_reply_id" => "fb-reply-200",
        "status" => "sent",
        "safe_error_code" => nil,
        "manual_evidence" => nil
      }
      expect(audit_event.event_type).to eq("auto_reply_sent")
      expect(audit_event.details).to eq(expected_details)

      selected_rule.update!(reply_text: "Câu trả lời đã được sửa.")
      expect(audit_event.reload.details).to eq(expected_details)
      expect { audit_event.update!(details: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end
end
