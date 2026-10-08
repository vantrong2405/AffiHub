require "rails_helper"

RSpec.describe AiProviderConnection, type: :model do
  describe "status" do
    it "uses the configured pending-verification default" do
      expect(build(:ai_provider_connection).status).to eq("pending_verification")
    end
  end

  describe "provider" do
    it "rejects the removed OpenAI provider" do
      connection = build(:ai_provider_connection, provider: "openai")

      expect(connection).not_to be_valid
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
      expect(connection.errors[:selected_model]).to eq([ "không thuộc danh sách model của kết nối" ])
    end
  end

  describe "credential storage" do
    it "encrypts access, refresh, and ID tokens at rest" do
      connection = create(
        :ai_provider_connection,
        access_token: "codex-access-secret",
        refresh_token: "codex-refresh-secret",
        id_token: "codex-id-secret"
      )
      persisted_connection = described_class.find(connection.id)

      expect(persisted_connection.access_token).to eq("codex-access-secret")
      expect(persisted_connection.refresh_token).to eq("codex-refresh-secret")
      expect(persisted_connection.id_token).to eq("codex-id-secret")
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("codex-access-secret"))
      expect(persisted_connection.read_attribute_before_type_cast(:refresh_token)).not_to match(Regexp.escape("codex-refresh-secret"))
      expect(persisted_connection.read_attribute_before_type_cast(:id_token)).not_to match(Regexp.escape("codex-id-secret"))
    end

    it "encrypts Gemini account credentials at rest" do
      connection = create(
        :ai_provider_connection,
        provider: "gemini",
        provider_client_id: "gemini-web-client",
        access_token: "gemini-private-access-token",
        refresh_token: "gemini-private-refresh-token",
        id_token: "gemini-private-id-token",
        scopes: [ "https://www.googleapis.com/auth/generative-language.retriever" ],
        available_models: [],
        selected_model: nil,
        status: :pending_verification
      )
      persisted_connection = described_class.find(connection.id)

      expect(persisted_connection).to have_attributes(
        access_token: "gemini-private-access-token",
        refresh_token: "gemini-private-refresh-token",
        id_token: "gemini-private-id-token"
      )
      expect(persisted_connection.read_attribute_before_type_cast(:access_token)).not_to match(Regexp.escape("gemini-private-access-token"))
      expect(persisted_connection.read_attribute_before_type_cast(:refresh_token)).not_to match(Regexp.escape("gemini-private-refresh-token"))
      expect(persisted_connection.read_attribute_before_type_cast(:id_token)).not_to match(Regexp.escape("gemini-private-id-token"))
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
      expect(duplicate.errors[:provider_subject]).to eq([ "đã được sử dụng" ])
    end
  end
end
