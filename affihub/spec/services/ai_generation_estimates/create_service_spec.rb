# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerationEstimates::CreateService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:first_scene) do
    { prompt: "A sunny bathroom", duration: 6, resolution: "480p", aspect_ratio: "9:16" }
  end
  let(:second_scene) do
    { prompt: "A skincare bottle on a shelf", duration: 6, resolution: "480p", aspect_ratio: "9:16" }
  end
  let(:scenes) { [ first_scene ] }
  let(:provider_costs) do
    {
      llm: { amount: nil, currency: "USD", provider: "Moonshot", source: "unknown" },
      stock: { amount: "0.00", currency: "USD", provider: "Pexels", source: "license" },
      tts_fallback: { amount: nil, currency: "USD", provider: "Azure Speech", source: "unknown" }
    }
  end
  let(:input_snapshot) { { model_id: "seedance-lite-t2v", scenes: scenes } }
  let(:service) do
    described_class.new(
      model_id: "seedance-lite-t2v",
      scenes: scenes,
      input_snapshot: input_snapshot,
      provider_costs: provider_costs
    )
  end
  let(:first_response) { { cost: "0.20", currency: "USD" }.to_json }
  let(:first_request) do
    stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
      .with(body: {
        "prompt" => first_scene[:prompt],
        "duration" => 6,
        "resolution" => "480p",
        "aspect_ratio" => "9:16"
      })
      .to_return(status: 200, body: first_response)
  end

  describe "#call" do
    before do
      travel_to(Time.zone.parse("2026-10-07 12:00:00"))
      first_request
    end

    after { travel_back }
    subject(:call_result) { service.call }
    subject(:scene_estimate) do
      service.call
      service.scene_estimates.first
    end

    it "returns the exact MuAPI quote for the scene input" do
      expect(scene_estimate).to eq(
        scene_number: 1,
        model_id: "seedance-lite-t2v",
        prompt: "A sunny bathroom",
        duration: 6,
        resolution: "480p",
        aspect_ratio: "9:16",
        amount: BigDecimal("0.20"),
        currency: "USD",
        source: "MuAPI estimate-cost",
        estimated_at: Time.zone.parse("2026-10-07 12:00:00")
      )
    end

    context "when there are multiple scenes" do
      let(:scenes) { [ first_scene, second_scene ] }
      let(:second_request) do
        stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
          .with(body: {
            "prompt" => second_scene[:prompt],
            "duration" => 6,
            "resolution" => "480p",
            "aspect_ratio" => "9:16"
          })
          .to_return(status: 200, body: { cost: "0.30", currency: "USD" }.to_json)
      end

      before { second_request }

      it "returns one estimate for each scene's exact input" do
        call_result

        expect(first_request).to have_been_requested.once
        expect(second_request).to have_been_requested.once
        expect(service.cost_breakdown.fetch(:muapi).fetch(:amount)).to eq("0.5")
      end
    end

    it "returns the cost breakdown categories in the expected order" do
      call_result

      expect(service.cost_breakdown.keys).to eq([ :muapi, :llm, :stock, :tts_fallback, :unknown ])
    end

    context "when MuAPI does not return a quote" do
      let(:first_response) { { currency: "USD" }.to_json }
      let(:provider_costs) do
        {
          llm: { amount: "0.08", currency: "USD", provider: "Moonshot", source: "estimate" },
          stock: { amount: "0.00", currency: "USD", provider: "Pexels", source: "license" },
          tts_fallback: { amount: "0.00", currency: "USD", provider: "VieNeu-TTS", source: "self-hosted" }
        }
      end

      it "returns an incomplete estimate with no total" do
        call_result

        expect(service.cost_breakdown.fetch(:muapi).fetch(:amount)).to be_nil
        expect(service.required_costs_known).to be(false)
        expect(service.total_amount).to be_nil
      end
    end

    context "when each provider has a quote in USD" do
      let(:provider_costs) do
        {
          llm: { amount: "0.08", currency: "USD", provider: "Moonshot", source: "estimate" },
          stock: { amount: "0.00", currency: "USD", provider: "Pexels", source: "license" },
          tts_fallback: { amount: "0.02", currency: "USD", provider: "Azure Speech", source: "estimate" }
        }
      end

      it "returns the total and marks required costs as known" do
        call_result

        expect(service.total_amount).to eq(BigDecimal("0.30"))
        expect(service.required_costs_known).to be(true)
      end
    end

    context "when provider quotes use different currencies" do
      let(:provider_costs) do
        {
          llm: { amount: "0.08", currency: "USD", provider: "Moonshot", source: "estimate" },
          stock: { amount: "0.00", currency: "USD", provider: "Pexels", source: "license" },
          tts_fallback: { amount: "0.02", currency: "EUR", provider: "Azure Speech", source: "estimate" }
        }
      end

      it "returns an incomplete estimate without summing currencies" do
        call_result

        expect(service.required_costs_known).to be(false)
        expect(service.total_amount).to be_nil
      end
    end
  end
end
