# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateScenePromptsService, type: :service do
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
  let(:service) do
    described_class.new(
      video_project:,
      ai_provider_connection_id: ai_provider_connection.id,
      model_id: "unverified-codex-model",
      video_subject: "Summer skincare",
      video_script: "A short summer skincare story.",
      script_approved: true,
      scene_count: 2
    )
  end
  let(:mpt_terms_request) do
    stub_request(:post, "http://mpt.test/api/v1/terms")
      .to_return(status: 200, body: { status: 200, data: { video_terms: [ "must not be used" ] } }.to_json)
  end
  let(:mpt_video_request) do
    stub_request(:post, "http://mpt.test/api/v1/videos")
      .to_return(status: 200, body: { status: 200, data: { task_id: "must-not-be-submitted" } }.to_json)
  end

  describe "#call" do
    it "returns false while Codex inference is unverified" do
      expect(Codex::Client).not_to receive(:new)

      expect(service.call).to eq(false)
      expect(service.scene_prompts).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end

    it "does not request terms from MoneyPrinterTurbo before AI inference is verified" do
      mpt_terms_request

      expect(service.call).to eq(false)

      expect(mpt_terms_request).not_to have_been_requested
    end

    it "does not submit a paid video job while Codex inference is unverified" do
      mpt_video_request

      expect(service.call).to eq(false)

      expect(mpt_video_request).not_to have_been_requested
    end

    context "when the script has not been approved" do
      let(:service) do
        described_class.new(
          video_project:,
          ai_provider_connection_id: ai_provider_connection.id,
          model_id: "unverified-codex-model",
          video_subject: "Summer skincare",
          video_script: "A short summer skincare story.",
          script_approved: false,
          scene_count: 2
        )
      end

      it "returns false before contacting the provider" do
        expect(Codex::Client).not_to receive(:new)

        expect(service.call).to eq(false)
        expect(service.errors.full_messages).to eq([ "Cần duyệt kịch bản trước khi tạo cảnh." ])
      end
    end
  end
end
