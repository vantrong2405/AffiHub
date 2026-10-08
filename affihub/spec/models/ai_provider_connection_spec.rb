require "rails_helper"

RSpec.describe AiProviderConnection, type: :model do
  describe "status" do
    it "uses the configured pending-verification default" do
      expect(build(:ai_provider_connection).status).to eq("pending_verification")
    end
  end

  describe "provider" do
    it "accepts the OpenAI provider" do
      connection = build(:ai_provider_connection, provider: "openai")

      expect(connection).to be_valid
    end

    it "accepts the Gemini provider" do
      connection = build(:ai_provider_connection, provider: "gemini")

      expect(connection).to be_valid
    end

    it "rejects the unavailable Antigravity provider" do
      connection = build(:ai_provider_connection, provider: "antigravity")

      expect(connection).not_to be_valid
    end
  end

  describe "selected model" do
    it "rejects a model absent from this connection's verified catalog" do
      connection = build(:ai_provider_connection, selected_model: "unlisted-model")

      expect(connection).not_to be_valid
      expect(connection.errors[:selected_model]).to include("không thuộc danh sách model của kết nối")
    end
  end

  describe "credential storage" do
    it "encrypts access, refresh, and ID tokens at rest" do
      connection = create(
        :ai_provider_connection,
        access_token: "openai-access-secret",
        refresh_token: "openai-refresh-secret",
        id_token: "openai-id-secret"
      )
      persisted_connection = described_class.find(connection.id)

      expect(persisted_connection.access_token).to eq("openai-access-secret")
      expect(persisted_connection.refresh_token).to eq("openai-refresh-secret")
      expect(persisted_connection.id_token).to eq("openai-id-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to include("openai-access-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:refresh_token)).not_to include("openai-refresh-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:id_token)).not_to include("openai-id-secret")
    end
  end

  describe "provider identity" do
    it "validates uniqueness of a provider account within its issued client registration" do
      connection = create(:ai_provider_connection)
      duplicate = build(
        :ai_provider_connection,
        provider: connection.provider,
        provider_subject: connection.provider_subject,
        provider_client_id: connection.provider_client_id
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider_subject]).to include("đã được sử dụng")
    end
  end
end
