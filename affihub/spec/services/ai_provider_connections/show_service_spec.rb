require "rails_helper"

RSpec.describe AiProviderConnections::ShowService, type: :service do
  describe "#call" do
    it "loads the requested provider account" do
      ai_provider_connection = create(:ai_provider_connection)
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to be(true)
      expect(service.ai_provider_connection).to eq(ai_provider_connection)
    end

    it "reports a missing provider account without loading another account" do
      service = described_class.new(ai_provider_connection_id: -1)

      expect(service.call).to be(false)
      expect(service.ai_provider_connection).to be_nil
      expect(service.errors.full_messages).to include("Không tìm thấy kết nối tài khoản AI.")
    end
  end
end
