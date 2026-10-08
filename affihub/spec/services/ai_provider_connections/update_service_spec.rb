require "rails_helper"

RSpec.describe AiProviderConnections::UpdateService, type: :service do
  let(:ai_provider_connection) { create(:ai_provider_connection) }

  describe "#call" do
    it "saves a model returned by this provider connection" do
      service = described_class.new(
        ai_provider_connection_id: ai_provider_connection.id,
        selected_model: "gpt-6-luna"
      )

      expect(service.call).to be(true)
      expect(ai_provider_connection.reload.selected_model).to eq("gpt-6-luna")
    end

    it "updates only the provider account selected by its connection ID" do
      selected_connection = create(
        :ai_provider_connection,
        available_models: [
          { "slug" => "gpt-6-luna", "display_name" => "GPT 6 Luna" },
          { "slug" => "gpt-6-luna-fast", "display_name" => "GPT 6 Luna Fast" }
        ],
        selected_model: "gpt-6-luna"
      )
      other_connection = create(:ai_provider_connection, selected_model: "gpt-6-luna")
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: "gpt-6-luna-fast"
      )

      expect(service.call).to be(true)
      expect(selected_connection.reload.selected_model).to eq("gpt-6-luna-fast")
      expect(other_connection.reload.selected_model).to eq("gpt-6-luna")
    end

    it "rejects a model that exists only in another provider account's catalog" do
      selected_connection = create(:ai_provider_connection, selected_model: "gpt-6-luna")
      other_connection = create(
        :ai_provider_connection,
        available_models: [ { "slug" => "other-account-model", "display_name" => "Other Account Model" } ],
        selected_model: "other-account-model"
      )
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: other_connection.selected_model
      )

      expect(service.call).to be(false)
      expect(selected_connection.reload.selected_model).to eq("gpt-6-luna")
      expect(other_connection.reload.selected_model).to eq("other-account-model")
      expect(service.errors.full_messages).to include("Model này không có trong danh sách của kết nối.")
    end

    it "rejects a Gemini model that exists only in another Google account's catalog" do
      selected_connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_subject: "google-model-owner-a",
        provider_client_id: "gemini-web-client",
        available_models: [ { "slug" => "models/gemini-flash-a", "display_name" => "Gemini Flash A" } ],
        selected_model: "models/gemini-flash-a"
      )
      other_connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_subject: "google-model-owner-b",
        provider_client_id: "gemini-web-client",
        available_models: [ { "slug" => "models/gemini-pro-b", "display_name" => "Gemini Pro B" } ],
        selected_model: "models/gemini-pro-b"
      )
      service = described_class.new(
        ai_provider_connection_id: selected_connection.id,
        selected_model: other_connection.selected_model
      )

      expect(service.call).to be(false)
      expect(selected_connection.reload.selected_model).to eq("models/gemini-flash-a")
      expect(other_connection.reload.selected_model).to eq("models/gemini-pro-b")
      expect(service.errors.full_messages).to include("Model này không có trong danh sách của kết nối.")
    end

    it "rejects a model absent from this connection and preserves the current selection" do
      service = described_class.new(
        ai_provider_connection_id: ai_provider_connection.id,
        selected_model: "model-from-another-account"
      )

      expect(service.call).to be(false)
      expect(ai_provider_connection.reload.selected_model).to eq("gpt-6-luna")
      expect(service.errors.full_messages).to include("Model này không có trong danh sách của kết nối.")
    end
  end
end
