# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateDraftService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:script_inputs) do
    {
      topic: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30
    }
  end
  let(:service) do
    described_class.new(
      video_project_id: video_project.id,
      inputs: script_inputs
    )
  end
  let(:script_request) do
    stub_request(:post, %r{/api/v1/scripts\z})
      .with(body: {
        "video_subject" => "Summer skincare",
        "video_language" => "vi",
        "paragraph_number" => 1,
        "video_script_prompt" => "Write a 30-second script in a friendly tone.",
        "custom_system_prompt" => ""
      })
      .to_return(
        status: 200,
        body: { status: 200, data: { video_script: "A short summer skincare story." } }.to_json
      )
  end

  describe "#call" do
    before { script_request }

    it "persists a script-ready generation with its input snapshot" do
      expect { service.call }.to change(AiGeneration, :count).by(1)

      expect(service).to be_success
      expect(service.ai_generation.status).to eq("script_ready")
      expect(service.ai_generation.input_snapshot).to include(
        "topic" => "Summer skincare",
        "video_subject" => "Summer skincare",
        "language" => "vi",
        "tone" => "friendly",
        "target_duration" => 30,
        "video_script" => "A short summer skincare story."
      )
      expect(service.ai_generation.video_project).to eq(video_project)
    end

    context "when the topic is blank" do
      let(:script_inputs) { super().merge(topic: " ") }

      it "returns invalid without requesting a script" do
        service.call

        expect(service).not_to be_success
        expect(script_request).not_to have_been_requested
        expect(AiGeneration.count).to eq(0)
      end
    end

    context "when MoneyPrinterTurbo rejects script generation" do
      let(:script_request) do
        stub_request(:post, %r{/api/v1/scripts\z})
          .to_return(status: 503, body: { error: "unavailable" }.to_json)
      end

      it "returns failure without persisting a generation" do
        expect { service.call }.not_to change(AiGeneration, :count)

        expect(service).not_to be_success
        expect(script_request).to have_been_requested.once
      end
    end
  end
end
