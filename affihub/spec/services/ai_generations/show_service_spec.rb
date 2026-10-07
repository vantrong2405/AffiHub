# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::ShowService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:ai_generation) { create(:ai_generation, video_project: video_project) }
  let(:service) do
    described_class.new(
      video_project_id: video_project.id,
      ai_generation_id: ai_generation.id
    )
  end

  describe "#call" do
    it "returns the AI generation owned by the selected project" do
      service.call

      expect(service.video_project).to eq(video_project)
      expect(service.ai_generation).to eq(ai_generation)
    end

    context "when the generation has an unresolved MPT submission" do
      let(:workflow_run) do
        create(
          :workflow_run,
          workflowable: ai_generation,
          operation: "ai_video_generation",
          stage: "mpt_video_submission"
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

      it "returns the submission attempt for the status page" do
        outbound_attempt
        service.call

        expect(service.outbound_attempt).to eq(outbound_attempt)
      end
    end

    context "when the generation belongs to another project" do
      let(:other_video_project) { create(:video_project) }
      let(:ai_generation) { create(:ai_generation, video_project: other_video_project) }

      it "raises not found" do
        expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
