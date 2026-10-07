require "rails_helper"

RSpec.describe "OutboundAttempts::ResolveService", type: :service do
  describe "#call" do
    it "returns failure while the previous sender may still be running" do
      attempt = create(:outbound_attempt, status: "outcome_unknown", sender_stopped_at: nil, request_timeout_at: 1.minute.ago)
      service = "OutboundAttempts::ResolveService".constantize.new(
        outbound_attempt_id: attempt.id,
        decision: :not_occurred,
        evidence: "Kiểm tra trang đích",
        actor_reference: "operator-1"
      )

      service.call

      expect(service).not_to be_success
      expect(attempt.reload.status).to eq("outcome_unknown")
    end

    it "returns failure until the maximum request window has ended" do
      attempt = create(:outbound_attempt, status: "outcome_unknown", sender_stopped_at: 1.minute.ago, request_timeout_at: 1.minute.from_now)
      service = "OutboundAttempts::ResolveService".constantize.new(
        outbound_attempt_id: attempt.id,
        decision: :not_occurred,
        evidence: "Không tìm thấy bài đăng",
        actor_reference: "operator-1"
      )

      service.call

      expect(service).not_to be_success
      expect(attempt.reload.status).to eq("outcome_unknown")
    end

    it "returns a manual decision and audit event after the sender and timeout are clear" do
      attempt = create(:outbound_attempt, status: "outcome_unknown", sender_stopped_at: 2.minutes.ago, request_timeout_at: 1.minute.ago)
      service = "OutboundAttempts::ResolveService".constantize.new(
        outbound_attempt_id: attempt.id,
        decision: :not_occurred,
        evidence: "Không tìm thấy bài đăng",
        actor_reference: "operator-1"
      )

      service.call

      expect(service).to be_success
      expect(attempt.reload.status).to eq("manual_outcome_not_occurred")
      expect(attempt.workflow_run.workflow_audit_events.sole.details.fetch("actor_reference")).to eq("operator-1")
    end

    it "returns a manual confirmation without claiming provider confirmation" do
      attempt = create(:outbound_attempt, status: "outcome_unknown")
      service = "OutboundAttempts::ResolveService".constantize.new(
        outbound_attempt_id: attempt.id, decision: :occurred, evidence: "Post đã xuất hiện", actor_reference: "operator-1"
      )

      service.call

      expect(attempt.reload.status).to eq("manual_outcome_confirmed")
      expect(attempt.workflow_run.reload.status).to eq("completed")
    end

    it "returns unresolved when the operator still cannot determine the outcome" do
      attempt = create(:outbound_attempt, status: "outcome_unknown")
      service = "OutboundAttempts::ResolveService".constantize.new(
        outbound_attempt_id: attempt.id,
        decision: :unknown,
        evidence: "Trang đích chưa cập nhật",
        actor_reference: "operator-1"
      )

      service.call

      expect(attempt.reload.status).to eq("outcome_unknown")
      expect(service).to be_success
      expect(attempt.workflow_run.workflow_audit_events.sole.details.fetch("decision")).to eq("unknown")
    end
  end
end
