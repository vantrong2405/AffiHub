# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateScenePromptsService, type: :service do
  let(:video_project) { create(:video_project) }
  let(:video_subject) { "Summer skincare" }
  let(:video_script) { "A short summer skincare story." }
  let(:script_approved) { true }
  let(:scene_count) { 2 }
  let(:service) do
    described_class.new(
      video_project: video_project,
      video_subject: video_subject,
      video_script: video_script,
      script_approved: script_approved,
      scene_count: scene_count
    )
  end
  let(:terms_request) do
    stub_request(:post, %r{/api/v1/terms\z})
      .with(body: {
        "video_subject" => "Summer skincare",
        "video_script" => "A short summer skincare story.",
        "amount" => 2,
        "match_materials_to_script" => true
      })
      .to_return(
        status: 200,
        body: { status: 200, data: { video_terms: [ "sunny bathroom", "skincare bottle" ] } }.to_json
      )
  end
  let(:video_request) do
    stub_request(:post, %r{/api/v1/videos\z})
      .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json)
  end

  describe "#call" do
    subject(:call_result) { service.call }

    before do
      terms_request
      video_request
    end

    context "when the script has not been approved" do
      let(:script_approved) { false }

      it "returns invalid without requesting scene prompts" do
        call_result

        expect(service.success?).to be(false)
        expect(terms_request).not_to have_been_requested
      end
    end

    it "returns the generated scene prompts from MPT" do
      call_result

      expect(service.scene_prompts).to eq([ "sunny bathroom", "skincare bottle" ])
      expect(terms_request).to have_been_requested.once
    end

    it "returns without submitting a paid video job" do
      call_result

      expect(video_request).not_to have_been_requested
    end
  end
end
