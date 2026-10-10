class SocialConnections::ProviderConfiguration
  # Loads provider settings from its YAML source and merges registry metadata.
  #
  # @param provider [String, Symbol] social provider key
  # @return [Hash] provider OAuth, API, and registry settings
  def self.for(provider)
    registry = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers)
    registry_configuration = registry.fetch(provider.to_sym)
    source = registry_configuration[:configuration_source]
    return registry_configuration unless source

    provider_configuration = Rails.application.config_for(source).deep_symbolize_keys
    oauth_configuration = provider_configuration.delete(:oauth) || {}
    provider_configuration.merge(oauth_configuration).merge(registry_configuration.except(:configuration_source))
  end
end
