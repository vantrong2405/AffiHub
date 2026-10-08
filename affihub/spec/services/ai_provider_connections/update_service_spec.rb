require "rails_helper"

RSpec.describe AiProviderConnections::UpdateService, type: :service do
  let(:ai_provider_connection) { create(:ai_provider_connection) }

  describe "#call" do
    it "saves a model returned by this provider connection" do
      ai_provider_connection.update!(
        available_models: [
          { "slug" => "models/gemini-3.5-flash-lite", "display_name" => "Gemini 3.5 Flash-Lite" },
          { "slug" => "models/gemini-3.5-flash", "display_name" => "Gemini 3.5 Flash" }
        ]
      )
      service = described_class.new(
        ai_provider_connection_id: ai_provider_connection.id,
        selected_model: "models/gemini-3.5-flash"
      )

      expect(service.call).to eq(true)
      expect(ai_provider_connection.reload.selected_model).to eq("models/gemini-3.5-flash")
    end

    it "updates only the provider account selected by its connection ID" do
      selected_connection = create(
        :ai_provider_connection,
        available_models: [
          { "slug" => "models/gemini-3.5-flash-lite", "display_name" => "Gemini 3.5 Flash-Lite" },
          { "slug" => "models/gemini-3.5-flash", "display_name" => "Gemini 3.5 Flash" }
        ],
        selected_model: "models/gemini-3.5-flash-lite"
      )
      other_connection = create(:ai_provider_connection, selected_model: "models/gemini-3.5-flash-lite")
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: "models/gemini-3.5-flash"
      )

      expect(service.call).to eq(true)
      expect(selected_connection.reload.selected_model).to eq("models/gemini-3.5-flash")
      expect(other_connection.reload.selected_model).to eq("models/gemini-3.5-flash-lite")
    end

    it "rejects a model that exists only in another provider account's catalog" do
      selected_connection = create(:ai_provider_connection, selected_model: "models/gemini-3.5-flash-lite")
      other_connection = create(
        :ai_provider_connection,
        available_models: [ { "slug" => "other-account-model", "display_name" => "Other Account Model" } ],
        selected_model: "other-account-model"
      )
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: other_connection.selected_model
      )

      expect(service.call).to eq(false)
      expect(selected_connection.reload.selected_model).to eq("models/gemini-3.5-flash-lite")
      expect(other_connection.reload.selected_model).to eq("other-account-model")
      expect(service.errors.full_messages).to eq([ "Model này không có trong danh sách của kết nối." ])
    end

    it "rejects a Gemini model that exists only in another Google account's catalog" do
      selected_connection = create(
        :ai_provider_connection,
        provider_subject: "google-model-owner-a",
        available_models: [ { "slug" => "models/gemini-flash-a", "display_name" => "Gemini Flash A" } ],
        selected_model: "models/gemini-flash-a"
      )
      other_connection = create(
        :ai_provider_connection,
        provider_subject: "google-model-owner-b",
        available_models: [ { "slug" => "models/gemini-pro-b", "display_name" => "Gemini Pro B" } ],
        selected_model: "models/gemini-pro-b"
      )
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: other_connection.selected_model
      )

      expect(service.call).to eq(false)
      expect(selected_connection.reload.selected_model).to eq("models/gemini-flash-a")
      expect(other_connection.reload.selected_model).to eq("models/gemini-pro-b")
      expect(service.errors.full_messages).to eq([ "Model này không có trong danh sách của kết nối." ])
    end

    it "rejects a model absent from this connection and preserves the current selection" do
      service = described_class.new(
        ai_provider_connection_id: ai_provider_connection.id,
        selected_model: "model-from-another-account"
      )

      expect(service.call).to eq(false)
      expect(ai_provider_connection.reload.selected_model).to eq("models/gemini-3.5-flash-lite")
      expect(service.errors.full_messages).to eq([ "Model này không có trong danh sách của kết nối." ])
    end
  end
end
