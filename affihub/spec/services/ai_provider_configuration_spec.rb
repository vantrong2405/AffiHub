require "rails_helper"

RSpec.describe AiProviderConfiguration, type: :service do
  describe ".for_client" do
    it "returns the YAML configuration associated with a provider client class" do
      configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys

      expect(described_class.for_client(client_class_name: "Gemini::Client")).to eq(
        configuration.fetch(:providers).fetch(:gemini)
      )
    end

    it "raises when a provider client class is not registered in YAML" do
      expect do
        described_class.for_client(client_class_name: "Unknown::Client")
      end.to raise_error(KeyError, "No AI provider configuration is registered for client Unknown::Client.")
    end
  end
end
