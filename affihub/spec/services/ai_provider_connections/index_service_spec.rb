require "rails_helper"

RSpec.describe AiProviderConnections::IndexService, type: :service do
  describe "#call" do
    let!(:connection) do
      create(
        :ai_provider_connection,
        provider: "codex",
        provider_subject: "codex-subject-123",
        provider_client_id: "codex-cli-client",
        scopes: %w[openid profile email offline_access],
        available_models: [],
        selected_model: nil,
        access_token: "codex-secret-token"
      )
    end
    let(:service) { described_class.new(current_origin: "http://localhost:3000") }

    before { expect(service.call).to eq(true) }

    it "returns the connected accounts" do
      expect(service.ai_provider_connections).to eq([ connection ])
    end

    it "returns the three configured product choices" do
      expect(service.provider_options).to eq(
        [
          {
            key: "codex", provider: "codex", label: "Codex", enabled: true,
            origin_matches: false, required_origin: "http://localhost:1455"
          },
          {
            key: "gemini", provider: "gemini", label: "Gemini API", enabled: true,
            origin_matches: true, required_origin: "http://localhost:3000"
          },
          {
            key: "antigravity", provider: "antigravity", label: "Antigravity", enabled: false,
            origin_matches: false, required_origin: nil
          }
        ]
      )
    end

    it "does not expose connected account credentials in provider options" do
      expect(service.provider_options.to_json).not_to match(Regexp.escape("codex-secret-token"))
    end

    it "returns provider presentations without credentials" do
      expect(service.provider_presentations.to_json).not_to match(Regexp.escape("affihub-test-gemini-secret"))
    end

    it "returns only the Gemini display name from its provider configuration" do
      expect(service.provider_presentations.fetch(:gemini)).to eq(display_name: "Gemini API")
    end

    it "returns the provider display name from YAML configuration" do
      configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
      configuration.fetch(:providers).fetch(:gemini)[:display_name] = "Configured Google provider"
      allow(Rails.application).to receive(:config_for).with(:ai_providers).and_return(configuration)
      service = described_class.new(current_origin: "http://localhost:3000")

      expect(service.call).to eq(true)
      gemini_option = service.provider_options.find { |option| option.fetch(:provider) == "gemini" }

      expect(gemini_option.fetch(:label)).to eq("Configured Google provider")
    end
  end
end
