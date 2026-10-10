class Publications::PublisherResolver < ApplicationService
  attr_reader :publisher_class

  # Initializes a provider-specific publisher resolver.
  #
  # @param provider [String, Symbol] the provider configured for a destination
  # @return [Publications::PublisherResolver] the configured resolver
  def initialize(provider:)
    @provider = provider.to_s
    super()
  end

  # Resolves the publisher implementation configured for a provider.
  #
  # @return [Boolean] whether a publisher is configured
  def call
    return false unless step_load_publisher

    step_succeed!
    success?
  end

  private

  def step_load_publisher
    providers = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers)
    provider_configuration = providers[@provider.to_sym]
    return step_fail!("Nhà cung cấp này chưa có publisher được cấu hình.") unless provider_configuration

    @publisher_class = provider_configuration.fetch(:publisher_service).constantize
    true
  rescue KeyError, NameError
    step_fail!("Không thể tải publisher đã cấu hình cho nhà cung cấp.")
  end
end
