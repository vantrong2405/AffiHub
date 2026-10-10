# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateDraftService, type: :service do
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
  let(:script_inputs) do
    {
      topic: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30,
      ai_provider_connection_id: ai_provider_connection.id
    }
  end
  let(:service) do
    described_class.new(video_project_id: video_project.id, inputs: script_inputs)
  end

  describe "#call" do
    it "returns failure without persisting a generation while Codex inference is unverified" do
      expect(Codex::Client).not_to receive(:new)

      expect { service.call }.not_to change(AiGeneration, :count)

      expect(service.success?).to eq(false)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end

    context "when the topic is blank" do
      let(:script_inputs) { super().merge(topic: " ") }

      it "returns failure without persisting a generation" do
        expect { service.call }.not_to change(AiGeneration, :count)

        expect(service.success?).to eq(false)
      end
    end
  end
end
