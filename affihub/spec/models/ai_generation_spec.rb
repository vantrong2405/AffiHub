# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGeneration, type: :model do
  describe "status" do
    it "returns draft for a newly built generation" do
      expect(build(:ai_generation).status).to eq("draft")
    end

    it "returns outcome unknown for a generation with an unresolved task" do
      ai_generation = build(:ai_generation, status: "outcome_unknown")

      expect(ai_generation.status).to eq("outcome_unknown")
    end
  end

  describe "video project association" do
    it "returns the assigned video project" do
      video_project = create(:video_project)
      ai_generation = create(:ai_generation, video_project:)

      expect(ai_generation.video_project).to eq(video_project)
    end
  end

  describe "workflow run association" do
    it "returns the workflow run assigned to the generation" do
      ai_generation = create(:ai_generation)
      workflow_run = create(:workflow_run, workflowable: ai_generation)

      expect(ai_generation.reload.workflow_run).to eq(workflow_run)
    end
  end

  describe "source asset association" do
    it "is valid before a source asset is generated" do
      ai_generation = build(:ai_generation, source_asset: nil)

      expect(ai_generation).to be_valid
    end

    context "when the source asset belongs to the same project" do
      let(:video_project) { create(:video_project) }
      let(:source_asset) { create(:source_asset, video_project:) }
      let(:ai_generation) { build(:ai_generation, video_project:, source_asset:) }

      it "is valid" do
        expect(ai_generation).to be_valid
      end
    end

    context "when the source asset belongs to another project" do
      let(:source_asset) { create(:source_asset) }
      let(:video_project) { create(:video_project) }
      let(:ai_generation) { build(:ai_generation, video_project:, source_asset:) }

      it "is invalid" do
        expect(ai_generation).not_to be_valid
      end
    end
  end

  describe "provider references" do
    it "persists the stable MPT correlation ID" do
      ai_generation = create(:ai_generation, correlation_id: "correlation-123")

      expect(ai_generation.reload.correlation_id).to eq("correlation-123")
    end

    it "persists the MPT task ID" do
      ai_generation = create(:ai_generation, task_id: "mpt-task-123")

      expect(ai_generation.reload.task_id).to eq("mpt-task-123")
    end
  end

  describe "saved snapshots" do
    it "persists the approved input snapshot" do
      input_snapshot = { topic: "Summer skincare", language: "vi" }
      ai_generation = create(:ai_generation, input_snapshot:)

      expect(ai_generation.reload.input_snapshot).to eq(input_snapshot.deep_stringify_keys)
    end

    it "persists the approved estimate snapshot" do
      estimate_snapshot = { total_amount: "0.50", currency: "USD" }
      ai_generation = create(:ai_generation, estimate_snapshot:)

      expect(ai_generation.reload.estimate_snapshot).to eq(estimate_snapshot.deep_stringify_keys)
    end

    it "persists the user's cost consent" do
      consent_snapshot = { confirmed: true, amount: "0.50", currency: "USD" }
      ai_generation = create(:ai_generation, consent_snapshot:)

      expect(ai_generation.reload.consent_snapshot).to eq(consent_snapshot.deep_stringify_keys)
    end

    it "persists the actual provider costs" do
      actual_costs = { muapi: { amount: "0.48", currency: "USD" } }
      ai_generation = create(:ai_generation, actual_costs:)

      expect(ai_generation.reload.actual_costs).to eq(actual_costs.deep_stringify_keys)
    end
  end

  describe "output attachments" do
    it "persists generated clips" do
      ai_generation = create(:ai_generation)
      ai_generation.clips.attach(
        io: StringIO.new("clip-bytes"),
        filename: "scene-1.mp4",
        content_type: "video/mp4"
      )

      expect(ai_generation.reload.clips.map { |clip| clip.filename.to_s }).to eq([ "scene-1.mp4" ])
    end

    it "persists the generated voiceover" do
      ai_generation = create(:ai_generation)
      ai_generation.voiceover.attach(
        io: StringIO.new("audio-bytes"),
        filename: "voiceover.wav",
        content_type: "audio/wav"
      )

      expect(ai_generation.reload.voiceover.filename.to_s).to eq("voiceover.wav")
    end

    it "persists generated subtitles" do
      ai_generation = create(:ai_generation)
      ai_generation.subtitle.attach(
        io: StringIO.new("subtitle-bytes"),
        filename: "subtitles.srt",
        content_type: "text/plain"
      )

      expect(ai_generation.reload.subtitle.filename.to_s).to eq("subtitles.srt")
    end

    it "persists the generated preview video" do
      ai_generation = create(:ai_generation)
      ai_generation.preview_video.attach(
        io: StringIO.new("preview-bytes"),
        filename: "preview.mp4",
        content_type: "video/mp4"
      )

      expect(ai_generation.reload.preview_video.filename.to_s).to eq("preview.mp4")
    end
  end
end
