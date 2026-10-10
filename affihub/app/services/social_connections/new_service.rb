class SocialConnections::NewService < ApplicationService
  attr_reader :provider, :provider_configured

  # Initializes the provider connection form service.
  #
  # @param provider [String, Symbol] the social provider to connect
  # @return [SocialConnections::NewService] the configured service
  def initialize(provider:)
    @provider = provider.to_s
    super()
  end

  # Reports whether the provider has its OAuth client and required parameters configured.
  #
  # @return [Boolean] whether the provider connection can start
  def call
    return false unless step_load_provider_configuration

    step_check_provider_configuration
    success?
  end

  private

  def step_load_provider_configuration
    @provider_configuration = SocialConnections::ProviderConfiguration.for(@provider)
    true
  rescue KeyError
    step_fail!("Nền tảng này chưa được cấu hình kết nối.")
  end

  def step_check_provider_configuration
    @provider_configured = @provider_configuration.fetch(:client_id, nil).present? && required_authorization_parameters_present?
    step_succeed!
  end

  def required_authorization_parameters_present?
    required_parameters = @provider_configuration.fetch(:required_authorization_parameters, [])
    authorization_params = @provider_configuration.fetch(:authorization_params, {})
    required_parameters.all? { |parameter| authorization_params[parameter].present? }
  end
end
