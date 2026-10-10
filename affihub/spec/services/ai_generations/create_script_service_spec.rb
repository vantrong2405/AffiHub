# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::CreateScriptService, type: :service do
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
  let(:service) { described_class.new(video_project:, inputs: script_inputs) }
  let(:mpt_script_request) do
    stub_request(:post, "http://mpt.test/api/v1/scripts")
      .to_return(status: 200, body: { status: 200, data: { video_script: "must not be used" } }.to_json)
  end

  describe "#call" do
    it "returns false while Codex is auth-only and inference remains unverified" do
      configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
      configuration.fetch(:providers).fetch(:codex)[:inference_disabled_message] = "Wrong YAML message"
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
      expect(Codex::Client).not_to receive(:new)

      expect(service.call).to eq(false)
      expect(service.script).to eq(nil)
      expect(service.errors.full_messages).to eq([ "Nhà cung cấp này chưa hỗ trợ tạo nội dung." ])
    end

    it "does not send an AI credential to the MoneyPrinterTurbo script endpoint" do
      mpt_script_request

      expect(service.call).to eq(false)

      expect(mpt_script_request).not_to have_been_requested
    end

    context "when the topic is missing" do
      let(:script_inputs) { super().except(:topic) }

      it "returns false without requesting a script" do
        mpt_script_request

        expect(service.call).to eq(false)
        expect(mpt_script_request).not_to have_been_requested
      end
    end

    context "when the connected account has not granted the required scope" do
      let(:ai_provider_connection) do
        create(:ai_provider_connection, status: :scope_missing, selected_model: nil)
      end

      it "returns false before calling the provider" do
        expect(Codex::Client).not_to receive(:new)

        expect(service.call).to eq(false)
        expect(service.errors.full_messages).to eq([ "Tài khoản AI chưa có quyền dùng model." ])
      end
    end
  end
end
