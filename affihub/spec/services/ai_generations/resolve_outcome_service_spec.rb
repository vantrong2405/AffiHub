# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::ResolveOutcomeService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:ai_generation) { create(:ai_generation, video_project: video_project, status: :outcome_unknown) }
  let(:workflow_run) do
    create(
      :workflow_run,
      workflowable: ai_generation,
      operation: "ai_video_generation",
      stage: "mpt_video_submission",
      status: "outcome_unknown"
    )
  end
  let(:outbound_attempt) do
    create(
      :outbound_attempt,
      workflow_run: workflow_run,
      stage: "mpt_video_submission",
      status: "outcome_unknown"
    )
  end
  let(:evidence) { "Task list chưa cho biết MPT đã nhận request hay chưa." }
  let(:service) do
    described_class.new(
      video_project_id: video_project.id,
      ai_generation_id: ai_generation.id,
      decision: "unknown",
      evidence: evidence,
      risk_confirmed: true
    )
  end

  describe "#call" do
    it "records the operator evidence on the generation's MPT attempt" do
      outbound_attempt
      service.call

      expect(service).to be_success
      expect(outbound_attempt.reload).to have_attributes(
        status: "outcome_unknown",
        manual_evidence: evidence,
        actor_reference: "local_operator"
      )
      expect(outbound_attempt.workflow_run.workflow_audit_events.sole.details).to eq(
        "decision" => "unknown",
        "evidence" => evidence,
        "actor_reference" => "local_operator"
      )
    end

    context "when the generation belongs to another project" do
      let(:other_video_project) { create(:video_project) }
      let(:ai_generation) { create(:ai_generation, video_project: other_video_project, status: :outcome_unknown) }

      it "raises not found without resolving the other project's attempt" do
        outbound_attempt

        expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
        expect(outbound_attempt.reload.status).to eq("outcome_unknown")
      end
    end
  end
end
