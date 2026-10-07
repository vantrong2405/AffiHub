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

  # Reports whether the provider has the public OAuth client ID configured.
  #
  # @return [Boolean] whether the provider connection can start
  def call
    return false unless step_load_provider_configuration

    step_check_provider_configuration
    success?
  end

  private

  def step_load_provider_configuration
    provider_configuration = Rails.application.config_for(:meta).deep_symbolize_keys
    @provider_configuration = provider_configuration.fetch(:providers).fetch(@provider.to_sym)
    true
  rescue KeyError
    step_fail!("Nền tảng này chưa được cấu hình kết nối.")
  end

  def step_check_provider_configuration
    @provider_configured = @provider_configuration.fetch(:client_id, nil).present?
    step_succeed!
  end
end
