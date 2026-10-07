# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateScriptService, type: :service do
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
      video_project: video_project,
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
    subject(:call_result) { service.call }

    it "returns the generated script from MoneyPrinterTurbo" do
      call_result

      expect(service.script).to eq("A short summer skincare story.")
      expect(script_request).to have_been_requested.once
    end

    context "when topic is missing" do
      let(:script_inputs) { super().except(:topic) }

      it "returns invalid without requesting a script" do
        call_result

        expect(service.success?).to be(false)
        expect(script_request).not_to have_been_requested
      end
    end
  end
end
