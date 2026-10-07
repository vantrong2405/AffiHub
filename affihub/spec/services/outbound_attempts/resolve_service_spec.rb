# frozen_string_literal: true

require "rails_helper"

RSpec.describe OutboundAttempts::ResolveService, type: :service do
  describe "#call" do
    let(:attempt) { create(:outbound_attempt, status: "outcome_unknown") }
    let(:service) do
      described_class.new(
        outbound_attempt_id: attempt.id,
        decision: :not_occurred,
        evidence: "Không tìm thấy bài đăng",
        actor_reference: "operator-1",
        risk_confirmed: true
      )
    end

    context "when the previous sender may still be running" do
      let(:attempt) do
        create(
          :outbound_attempt,
          status: "outcome_unknown",
          sender_stopped_at: nil,
          request_timeout_at: 1.minute.ago
        )
      end

      it "returns failure and keeps the attempt outcome unknown" do
        service.call

        expect(service).not_to be_success
        expect(attempt.reload.status).to eq("outcome_unknown")
      end
    end

    context "when the maximum request window has not ended" do
      let(:attempt) do
        create(
          :outbound_attempt,
          status: "outcome_unknown",
          sender_stopped_at: 1.minute.ago,
          request_timeout_at: 1.minute.from_now
        )
      end

      it "returns failure and keeps the attempt outcome unknown" do
        service.call

        expect(service).not_to be_success
        expect(attempt.reload.status).to eq("outcome_unknown")
      end
    end

    context "when the provider request did not occur" do
      let(:attempt) do
        create(
          :outbound_attempt,
          status: "outcome_unknown",
          sender_stopped_at: 2.minutes.ago,
          request_timeout_at: 1.minute.ago
        )
      end

      it "marks the attempt as not occurred and requeues the workflow" do
        service.call

        expect(service).to be_success
        expect(attempt.reload.status).to eq("manual_outcome_not_occurred")
        expect(attempt.workflow_run.reload.status).to eq("queued")
        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "not_occurred",
          "evidence" => "Không tìm thấy bài đăng",
          "actor_reference" => "operator-1",
          "risk_confirmed" => true
        )
      end
    end

    context "when the provider request occurred" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :occurred,
          evidence: "Post đã xuất hiện",
          actor_reference: "operator-1",
          provider_reference: "https://mpt.example/tasks/mpt-task-123"
        )
      end

      it "marks the attempt as occurred and completes the workflow" do
        service.call

        expect(attempt.reload.status).to eq("manual_outcome_confirmed")
        expect(attempt.provider_reference).to include(
          "manual_reference" => "https://mpt.example/tasks/mpt-task-123"
        )
        expect(attempt.workflow_run.reload.status).to eq("completed")
        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "occurred",
          "evidence" => "Post đã xuất hiện",
          "actor_reference" => "operator-1",
          "provider_reference" => "https://mpt.example/tasks/mpt-task-123"
        )
      end
    end

    context "when the operator cannot determine the outcome" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :unknown,
          evidence: "Trang đích chưa cập nhật",
          actor_reference: "operator-1",
          risk_confirmed: true
        )
      end

      it "keeps the attempt unresolved and records the operator decision" do
        service.call

        expect(service).to be_success
        expect(attempt.reload.status).to eq("outcome_unknown")
        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "unknown",
          "evidence" => "Trang đích chưa cập nhật",
          "actor_reference" => "operator-1"
        )
      end
    end

    context "when the operator marks the request as not occurred without confirming the retry risk" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :not_occurred,
          evidence: "Không tìm thấy task",
          actor_reference: "operator-1",
          risk_confirmed: false
        )
      end

      it "returns failure and keeps the attempt unresolved" do
        service.call

        expect(service).not_to be_success
        expect(attempt.reload.status).to eq("outcome_unknown")
      end
    end

    context "when the operator marks the request as occurred without a provider reference" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :occurred,
          evidence: "Tác vụ xuất hiện trong tài khoản provider",
          actor_reference: "operator-1",
          provider_reference: nil
        )
      end

      it "returns failure and keeps the attempt unresolved" do
        service.call

        expect(service).not_to be_success
        expect(attempt.reload.status).to eq("outcome_unknown")
      end
    end
  end
end
