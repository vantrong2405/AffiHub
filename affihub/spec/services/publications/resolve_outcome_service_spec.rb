require "rails_helper"

RSpec.describe Publications::ResolveOutcomeService, type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:publication) do
      create(
        :publication,
        status: "outcome_unknown",
        platform_post_id: "video-1",
        provider_reference: { "provider" => "facebook", "video_id" => "video-1" }
      )
    end
    let(:workflow_run) do
      create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "outcome_unknown",
        checkpoint: { "video_id" => "video-1", "upload_complete" => true, "finish_acknowledged" => true }
      )
    end
    let!(:outbound_attempt) do
      create(
        :outbound_attempt,
        workflow_run:,
        status: "outcome_unknown",
        sender_stopped_at: 2.minutes.ago,
        request_timeout_at: 1.minute.ago
      )
    end
    let(:service) do
      described_class.new(
        video_project_id: publication.render_version.video_project_id,
        publication_id: publication.id,
        decision: "unknown",
        evidence: "Trang Page chưa cập nhật",
        actor_reference: "operator-1"
      )
    end

    it "keeps the outcome unresolved and records the operator's evidence" do
      service.call

      expect(service).to be_success
      expect(publication.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.workflow_audit_events.sole.details).to eq(
        "decision" => "unknown",
        "evidence" => "Trang Page chưa cập nhật",
        "actor_reference" => "operator-1"
      )
    end

    context "when the operator confirms that the post occurred" do
      let(:service) do
        described_class.new(
          video_project_id: publication.render_version.video_project_id,
          publication_id: publication.id,
          decision: "occurred",
          evidence: "Đã kiểm tra bài trên Page",
          actor_reference: "operator-1",
          provider_reference: "https://facebook.com/reel/1"
        )
      end

      it "records manual confirmation without marking the Publication published" do
        service.call

        expect(service).to be_success
        expect(publication.reload.status).to eq("manual_outcome_confirmed")
        expect(publication.published_at).to be_nil
        expect(publication.provider_reference).to include(
          "manual_reference" => "https://facebook.com/reel/1"
        )
        expect(workflow_run.reload.workflow_audit_events.sole.details).to eq(
          "decision" => "occurred",
          "evidence" => "Đã kiểm tra bài trên Page",
          "actor_reference" => "operator-1",
          "provider_reference" => "https://facebook.com/reel/1"
        )
      end
    end

    context "when the operator confirms that the post did not occur" do
      let(:service) do
        described_class.new(
          video_project_id: publication.render_version.video_project_id,
          publication_id: publication.id,
          decision: "not_occurred",
          evidence: "Đã kiểm tra và không thấy bài trên Page",
          actor_reference: "operator-1",
          risk_confirmed: true
        )
      end

      it "records the decision, audit event, and safe retry state" do
        expect { service.call }.to have_enqueued_job(Publications::PublishJob).with(workflow_run.id)

        expect(service).to be_success
        expect(publication.reload.status).to eq("manual_outcome_not_occurred")
        expect(publication.platform_post_id).to be_nil
        expect(publication.provider_reference).to eq({})
        expect(workflow_run.reload.status).to eq("queued")
        expect(workflow_run.checkpoint).to eq({})
        expect(workflow_run.workflow_audit_events.sole.details).to eq(
          "decision" => "not_occurred",
          "evidence" => "Đã kiểm tra và không thấy bài trên Page",
          "actor_reference" => "operator-1",
          "risk_confirmed" => true
        )
      end
    end

    context "when the previous sender has not stopped" do
      let(:outbound_attempt) do
        create(
          :outbound_attempt,
          workflow_run:,
          status: "outcome_unknown",
          sender_stopped_at: nil,
          request_timeout_at: 1.minute.ago
        )
      end
      let(:service) do
        described_class.new(
          video_project_id: publication.render_version.video_project_id,
          publication_id: publication.id,
          decision: "not_occurred",
          evidence: "Không tìm thấy bài trên Page",
          actor_reference: "operator-1",
          risk_confirmed: true
        )
      end

      it "keeps the Publication unresolved and writes no resolution audit" do
        service.call

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("outcome_unknown")
        expect(workflow_run.workflow_audit_events).to be_empty
      end
    end
  end
end
