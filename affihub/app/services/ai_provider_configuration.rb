class AiProviderConfiguration
  # Returns the provider settings that register an external client class.
  #
  # @param client_class_name [String] the fully qualified external client class name
  # @return [Hash] the provider configuration loaded from YAML
  # @raise [KeyError] when no provider registers the client class
  def self.for_client(client_class_name:)
    provider_configurations = Rails.application.config_for(:ai_providers).deep_symbolize_keys.fetch(:providers)
    provider_configuration = provider_configurations.values.find do |configuration|
      configuration.fetch(:clients, {}).value?(client_class_name.to_s)
    end
    return provider_configuration if provider_configuration

    raise KeyError, "No AI provider configuration is registered for client #{client_class_name}."
  end
end
