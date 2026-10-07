# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerationScene, type: :model do
  describe "scene index" do
    it "rejects a duplicate index in the same generation" do
      ai_generation = create(:ai_generation)
      create(:ai_generation_scene, ai_generation:, scene_index: 0)
      duplicate_scene = build(:ai_generation_scene, ai_generation:, scene_index: 0)

      expect(duplicate_scene).not_to be_valid
    end

    it "allows the same index in another generation" do
      create(:ai_generation_scene, scene_index: 0)
      other_scene = build(:ai_generation_scene, scene_index: 0)

      expect(other_scene).to be_valid
    end

    it "returns scenes in index order" do
      ai_generation = create(:ai_generation)
      second_scene = create(:ai_generation_scene, ai_generation:, scene_index: 1)
      first_scene = create(:ai_generation_scene, ai_generation:, scene_index: 0)

      expect(described_class.in_order.to_a).to eq([ first_scene, second_scene ])
    end
  end

  describe "workflow run association" do
    it "returns the workflow run that owns the scene" do
      ai_generation_scene = create(:ai_generation_scene)
      workflow_run = create(:workflow_run, workflowable: ai_generation_scene, operation: "tts_fallback")

      expect(ai_generation_scene.reload.workflow_run).to eq(workflow_run)
    end
  end

  describe "voiceover attachment" do
    it "persists the scene's generated voiceover" do
      ai_generation_scene = create(:ai_generation_scene)
      ai_generation_scene.voiceover.attach(
        io: StringIO.new("RIFF0000WAVEaudio-data"),
        filename: "scene-1.wav",
        content_type: "audio/wav"
      )

      expect(ai_generation_scene.reload.voiceover.filename.to_s).to eq("scene-1.wav")
    end
  end
end
