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
