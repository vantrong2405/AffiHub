# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreatePromptsService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:input_snapshot) do
    {
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
      video_project: video_project,
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
  let(:terms_request) do
    stub_request(:post, %r{/api/v1/terms\z})
      .with(body: {
        "video_subject" => "Summer skincare",
        "video_script" => video_script,
        "amount" => 2,
        "match_materials_to_script" => true
      })
      .to_return(
        status: 200,
        body: { status: 200, data: { video_terms: [ "sunny bathroom", "skincare bottle" ] } }.to_json
      )
  end

  describe "#call" do
    before { terms_request }

    it "saves scene prompts as unapproved inputs after script approval" do
      service.call

      expect(service).to be_success
      expect(ai_generation.reload.status).to eq("prompts_ready")
      expect(ai_generation.input_snapshot).to include(
        "video_script" => video_script,
        "script_approved" => true,
        "scenes" => [
          {
            "prompt" => "sunny bathroom",
            "duration" => 6,
            "resolution" => "480p",
            "aspect_ratio" => "9:16",
            "approved" => false
          },
          {
            "prompt" => "skincare bottle",
            "duration" => 6,
            "resolution" => "480p",
            "aspect_ratio" => "9:16",
            "approved" => false
          }
        ]
      )
    end

    context "when the user has not approved the script" do
      let(:script_approved) { false }

      it "returns failure without requesting scene prompts" do
        service.call

        expect(service).not_to be_success
        expect(terms_request).not_to have_been_requested
        expect(ai_generation.reload.input_snapshot.fetch("script_approved")).to be(false)
      end
    end

    context "when the approved script has changed" do
      let(:video_script) { "A revised skincare story." }
      let(:estimate_snapshot) { { total_amount: "0.50" } }

      it "saves the script and invalidates the previous estimate" do
        service.call

        expect(ai_generation.reload.input_snapshot.fetch("video_script")).to eq(video_script)
        expect(ai_generation.estimate_snapshot).to eq({})
      end
    end
  end
end
