# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreatePromptsService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:ai_provider_connection) do
    create(
      :ai_provider_connection,
      provider: "codex",
      status: :pending_verification,
      available_models: [],
      selected_model: nil
    )
  end
  let(:input_snapshot) do
    {
      ai_provider_connection_id: ai_provider_connection.id,
      llm_provider: "codex",
      llm_model: nil,
      topic: "Summer skincare",
      video_subject: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30,
      model_id: "seedance-lite-t2v",
      resolution: "480p",
      scene_count: 2,
      scene_duration: 6,
      video_script: "A short summer skincare story.",
      script_approved: false,
      scenes: []
    }
  end
  let(:estimate_snapshot) { {} }
  let(:ai_generation) do
    create(
      :ai_generation,
      video_project:,
      status: :script_ready,
      input_snapshot: input_snapshot,
      estimate_snapshot: estimate_snapshot
    )
  end
  let(:video_script) { "A short summer skincare story." }
  let(:script_approved) { true }
  let(:service) do
    described_class.new(
      video_project_id: video_project.id,
      ai_generation_id: ai_generation.id,
      video_script: video_script,
      script_approved: script_approved
    )
  end

  describe "#call" do
    it "saves the approved script but returns failure while Codex inference is unverified" do
      expect(Codex::Client).not_to receive(:new)

      expect(service.call).to eq(false)
      expect(ai_generation.reload.status).to eq("script_ready")
      expect(ai_generation.input_snapshot.slice("video_script", "script_approved", "scenes")).to eq(
        "video_script" => video_script,
        "script_approved" => true,
        "scenes" => []
      )
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end

    context "when the user has not approved the script" do
      let(:script_approved) { false }

      it "returns false without changing the generation" do
        expect(service.call).to eq(false)

        expect(ai_generation.reload.input_snapshot.fetch("script_approved")).to eq(false)
        expect(ai_generation.status).to eq("script_ready")
      end
    end

    context "when the approved script has changed" do
      let(:video_script) { "A revised skincare story." }
      let(:estimate_snapshot) { { total_amount: "0.50" } }

      it "saves the approved script and clears its estimate before the inference gate blocks prompts" do
        expect(service.call).to eq(false)

        expect(ai_generation.reload.input_snapshot.fetch("video_script")).to eq(video_script)
        expect(ai_generation.estimate_snapshot).to eq({})
      end
    end
  end
end
