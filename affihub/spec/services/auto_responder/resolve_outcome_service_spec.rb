require "rails_helper"

RSpec.describe "AutoResponder::ResolveOutcomeService", type: :service do
  describe "#call" do
    let(:destination) { create(:social_destination, provider: "facebook") }
    let(:event) do
      AutoReplyEvent.create!(
        social_destination: destination,
        source: "facebook",
        event_type: "comment",
        provider_comment_id: "fb-comment-100",
        comment_text: "Mẫu này còn hàng không?",
        status: "outcome_unknown"
      )
    end
    let(:workflow_run) do
      WorkflowRun.create!(
        workflowable: event,
        operation_id: "auto-reply-#{SecureRandom.uuid}",
        operation: "auto_reply",
        stage: "reply",
        status: "outcome_unknown"
      )
    end
    let(:outbound_attempt) do
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "reply",
        status: "outcome_unknown",
        sender_stopped_at: 2.minutes.ago,
        request_timeout_at: 1.minute.ago
      )
    end

    it "returns manual_outcome_confirmed without marking the reply as sent when the operator confirms occurrence" do
      service = described_class.new(
        auto_reply_event_id: event.id,
        decision: "occurred",
        provider_reference: "https://facebook.com/comments/fb-reply-200",
        evidence: "Đã thấy phản hồi trên Page.",
        actor_reference: "operator-1"
      )
      outbound_attempt

      expect(service.call).to eq(true)

      expect(event.reload.status).to eq("manual_outcome_confirmed")
      expect(outbound_attempt.reload.status).to eq("manual_outcome_confirmed")
      expect(workflow_run.reload.workflow_audit_events.order(:created_at).last.details).to eq(
        "decision" => "occurred",
        "provider_reference" => "https://facebook.com/comments/fb-reply-200",
        "evidence" => "Đã thấy phản hồi trên Page.",
        "actor_reference" => "operator-1",
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id
      )
    end

    it "returns manual_outcome_not_occurred only after the operator confirms retry risk" do
      service = described_class.new(
        auto_reply_event_id: event.id,
        decision: "not_occurred",
        evidence: "Không thấy phản hồi trong bài đăng.",
        actor_reference: "operator-1",
        risk_confirmed: true
      )
      outbound_attempt

      expect(service.call).to eq(true)

      expect(event.reload.status).to eq("manual_outcome_not_occurred")
      expect(outbound_attempt.reload.status).to eq("manual_outcome_not_occurred")
      expect(workflow_run.reload.status).to eq("queued")
      expect(workflow_run.workflow_audit_events.order(:created_at).last.details).to eq(
        "decision" => "not_occurred",
        "evidence" => "Không thấy phản hồi trong bài đăng.",
        "actor_reference" => "operator-1",
        "risk_confirmed" => true,
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id
      )
    end

    it "returns outcome_unknown when the operator cannot determine whether the reply occurred" do
      service = described_class.new(
        auto_reply_event_id: event.id,
        decision: "unknown",
        evidence: "Không đủ dữ liệu để xác định.",
        actor_reference: "operator-1"
      )
      outbound_attempt

      expect(service.call).to eq(true)

      expect(event.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("outcome_unknown")
      expect(workflow_run.workflow_audit_events.order(:created_at).last.details).to eq(
        "decision" => "unknown",
        "evidence" => "Không đủ dữ liệu để xác định.",
        "actor_reference" => "operator-1",
        "source" => "facebook",
        "event_type" => "comment",
        "social_destination_id" => destination.id
      )
    end

    it "returns failure when the operator does not confirm retry risk" do
      service = described_class.new(
        auto_reply_event_id: event.id,
        decision: "not_occurred",
        evidence: "Không thấy phản hồi trong bài đăng.",
        actor_reference: "operator-1",
        risk_confirmed: false
      )
      outbound_attempt

      expect(service.call).to eq(false)

      expect(event.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("outcome_unknown")
    end
  end
end
