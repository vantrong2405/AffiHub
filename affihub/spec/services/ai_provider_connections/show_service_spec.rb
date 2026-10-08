require "rails_helper"

RSpec.describe AiProviderConnections::ShowService, type: :service do
  describe "#call" do
    it "returns the requested provider account" do
      ai_provider_connection = create(:ai_provider_connection)
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to be(true)
      expect(service.ai_provider_connection).to eq(ai_provider_connection)
    end

    it "returns only safe presentation and permission settings to the view" do
      ai_provider_connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_client_id: "gemini-test-client",
        status: :pending_verification,
        selected_model: nil
      )
      service = described_class.new(ai_provider_connection_id: ai_provider_connection.id)

      expect(service.call).to be(true)
      expect(service.provider_presentation.slice(:display_name, :required_scopes)).to eq(
        display_name: "Gemini API",
        required_scopes: [ "https://www.googleapis.com/auth/generative-language.retriever" ]
      )
      expect(service.provider_presentation.to_json).not_to match(Regexp.escape("affihub-test-gemini-secret"))
      expect(service.provider_presentation).not_to have_key(:client_secret)
    end

    it "reports a missing provider account without loading another account" do
      service = described_class.new(ai_provider_connection_id: -1)

      expect(service.call).to be(false)
      expect(service.ai_provider_connection).to be_nil
      expect(service.errors.full_messages).to eq([ "Không tìm thấy kết nối tài khoản AI." ])
    end
  end
end
