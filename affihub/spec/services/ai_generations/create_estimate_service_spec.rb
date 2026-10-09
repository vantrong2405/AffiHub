# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateEstimateService, type: :service do
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
      script_approved: true,
      scenes: [
        { prompt: "A sunny bathroom", duration: 6, resolution: "480p", aspect_ratio: "9:16", approved: true },
        { prompt: "A skincare bottle", duration: 6, resolution: "480p", aspect_ratio: "9:16", approved: true }
      ]
    }
  end
  let(:estimate_snapshot) { {} }
  let(:ai_generation) do
    create(
      :ai_generation,
      video_project: video_project,
      status: :prompts_ready,
      input_snapshot: input_snapshot,
      estimate_snapshot: estimate_snapshot
    )
  end
  let(:scene_inputs) { input_snapshot.fetch(:scenes) }
  let(:service) do
    described_class.new(
      video_project_id: video_project.id,
      ai_generation_id: ai_generation.id,
      scenes: scene_inputs
    )
  end
  let(:first_estimate_request) do
    stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
      .with(body: {
        "prompt" => "A sunny bathroom",
        "duration" => 6,
        "resolution" => "480p",
        "aspect_ratio" => "9:16"
      })
      .to_return(status: 200, body: { cost: "0.20", currency: "USD" }.to_json)
  end
  let(:second_estimate_request) do
    stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
      .with(body: {
        "prompt" => "A skincare bottle",
        "duration" => 6,
        "resolution" => "480p",
        "aspect_ratio" => "9:16"
      })
      .to_return(status: 200, body: { cost: "0.30", currency: "USD" }.to_json)
  end

  describe "#call" do
    before do
      first_estimate_request
      second_estimate_request
    end

    it "persists estimates tied to the approved scene inputs" do
      service.call

      expect(service).to be_success
      expect(ai_generation.reload.estimate_snapshot.fetch("input_snapshot")).to eq(ai_generation.input_snapshot)
      expect(ai_generation.estimate_snapshot.dig("cost_breakdown", "muapi", "amount")).to eq("0.5")
      expect(ai_generation.estimate_snapshot.fetch("required_costs_known")).to be(false)
      expect(first_estimate_request).to have_been_requested.once
      expect(second_estimate_request).to have_been_requested.once
    end

    context "when a scene is not approved" do
      let(:scene_inputs) do
        [ super().first.merge(approved: false), super().last ]
      end
      let(:estimate_snapshot) { { total_amount: "0.50" } }

      it "clears the previous estimate without requesting a quote" do
        service.call

        expect(service).not_to be_success
        expect(ai_generation.reload.estimate_snapshot).to eq({})
        expect(first_estimate_request).not_to have_been_requested
        expect(second_estimate_request).not_to have_been_requested
      end
    end

    context "when scene durations differ" do
      let(:scene_inputs) do
        [
          input_snapshot.fetch(:scenes).first,
          input_snapshot.fetch(:scenes).last.merge(duration: 5)
        ]
      end

      it "returns failure without requesting estimates" do
        service.call

        expect(service).not_to be_success
        expect(first_estimate_request).not_to have_been_requested
        expect(second_estimate_request).not_to have_been_requested
      end
    end

    context "when Gemini is selected without verified project pricing" do
      let(:input_snapshot) do
        super().merge(llm_provider: "gemini", llm_model: "models/gemini-3.8-flash")
      end

      it "persists Gemini cost as unknown and leaves the total amount unset" do
        service.call

        estimate = ai_generation.reload.estimate_snapshot.deep_symbolize_keys

        expect(estimate.dig(:cost_breakdown, :llm).slice(:amount, :provider, :source)).to eq(
          amount: nil,
          provider: "LLM",
          source: "unknown"
        )
        expect(estimate.dig(:cost_breakdown, :unknown, :source)).to eq("llm,tts_fallback")
        expect(estimate.fetch(:required_costs_known)).to be(false)
        expect(estimate.fetch(:total_amount)).to be_nil
      end
    end
  end
end
