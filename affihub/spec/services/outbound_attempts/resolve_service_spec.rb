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
        actor_reference: "operator-1"
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

      it "returns failure" do
        service.call

        expect(service).not_to be_success
      end

      it "keeps the attempt outcome unknown" do
        service.call

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

      it "returns failure" do
        service.call

        expect(service).not_to be_success
      end

      it "keeps the attempt outcome unknown" do
        service.call

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

      it "returns success" do
        service.call

        expect(service).to be_success
      end

      it "marks the attempt as manually not occurred" do
        service.call

        expect(attempt.reload.status).to eq("manual_outcome_not_occurred")
      end

      it "queues the workflow for retry" do
        service.call

        expect(attempt.workflow_run.reload.status).to eq("queued")
      end

      it "records the operator decision in the audit event" do
        service.call

        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "not_occurred",
          "evidence" => "Không tìm thấy bài đăng",
          "actor_reference" => "operator-1"
        )
      end
    end

    context "when the provider request occurred" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :occurred,
          evidence: "Post đã xuất hiện",
          actor_reference: "operator-1"
        )
      end

      it "marks the attempt as manually confirmed" do
        service.call

        expect(attempt.reload.status).to eq("manual_outcome_confirmed")
      end

      it "completes the workflow" do
        service.call

        expect(attempt.workflow_run.reload.status).to eq("completed")
      end

      it "records the operator decision in the audit event" do
        service.call

        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "occurred",
          "evidence" => "Post đã xuất hiện",
          "actor_reference" => "operator-1"
        )
      end
    end

    context "when the operator cannot determine the outcome" do
      let(:service) do
        described_class.new(
          outbound_attempt_id: attempt.id,
          decision: :unknown,
          evidence: "Trang đích chưa cập nhật",
          actor_reference: "operator-1"
        )
      end

      it "returns success" do
        service.call

        expect(service).to be_success
      end

      it "keeps the attempt outcome unknown" do
        service.call

        expect(attempt.reload.status).to eq("outcome_unknown")
      end

      it "records the operator decision in the audit event" do
        service.call

        expect(attempt.workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "unknown",
          "evidence" => "Trang đích chưa cập nhật",
          "actor_reference" => "operator-1"
        )
      end
    end
  end
end
