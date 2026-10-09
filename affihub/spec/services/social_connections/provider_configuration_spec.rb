require "rails_helper"

RSpec.describe SocialConnections::ProviderConfiguration, type: :service do
  describe ".for" do
    it "returns merged TikTok API and OAuth settings from its provider YAML" do
      configuration = described_class.for(:tiktok)
      expected_configuration = Rails.application.config_for(:tiktok).deep_symbolize_keys
      oauth_configuration = expected_configuration.delete(:oauth)
      registry_configuration = Rails.application.config_for(:meta)
        .deep_symbolize_keys
        .fetch(:providers)
        .fetch(:tiktok)
      expected_configuration.merge!(oauth_configuration)
      expected_configuration.merge!(registry_configuration.except(:configuration_source))

      expect(configuration).to eq(expected_configuration)
    end

  end
end
