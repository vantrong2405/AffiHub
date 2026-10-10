class AiProviderConnections::IndexService < ApplicationService
  attr_reader :ai_provider_connections, :provider_options, :provider_presentations

  # Initializes the provider-account list read action.
  #
  # @param current_origin [String] the browser origin displaying the settings page
  # @return [AiProviderConnections::IndexService] the configured service
  def initialize(current_origin:)
    @current_origin = current_origin
    super()
  end

  # Loads provider accounts and the supported product choices.
  #
  # @return [Boolean] whether the list was loaded
  def call
    return false unless step_load_provider_accounts
    return false unless step_load_provider_options

    step_succeed!
    success?
  end

  private

  def step_load_provider_accounts
    @ai_provider_connections = AiProviderConnection.order(created_at: :desc)
    true
  end

  def step_load_provider_options
    @configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    provider_configurations = @configuration.fetch(:providers)
    @provider_presentations = provider_configurations.transform_values do |provider_configuration|
      provider_configuration.slice(:display_name)
    end
    @provider_options = provider_configurations
      .sort_by { |_provider, provider_configuration| provider_configuration.fetch(:display_order) }
      .map { |provider, provider_configuration| step_provider_option(provider, provider_configuration) }
    true
  rescue KeyError, URI::InvalidURIError
    step_fail!("Không thể tải cấu hình kết nối tài khoản AI.")
  end

  def step_provider_option(provider, provider_configuration)
    provider_key = provider.to_s
    callback_origin = step_callback_origin(provider_configuration)
    {
      key: provider_configuration.fetch(:option_key).to_s,
      provider: provider_key,
      label: provider_configuration.fetch(:display_name),
      enabled: step_provider_configured?(provider_configuration),
      origin_matches: callback_origin.present? && step_same_origin?(callback_origin, @current_origin),
      required_origin: callback_origin
    }
  end

  def step_provider_configured?(provider_configuration)
    return false unless provider_configuration.fetch(:enabled)

    requirements = provider_configuration.fetch(:configuration_requirements, {})
    missing_shared_setting = requirements.fetch(:shared, []).any? do |key|
      @configuration.fetch(key.to_sym).blank?
    end
    missing_provider_setting = requirements.fetch(:provider, []).any? do |key|
      provider_configuration.fetch(key.to_sym).blank?
    end

    !missing_shared_setting && !missing_provider_setting
  end

  def step_callback_origin(provider_configuration)
    return unless provider_configuration.key?(:redirect_uri)

    step_uri_origin(provider_configuration.fetch(:redirect_uri))
  end

  def step_same_origin?(first_origin, second_origin)
    step_uri_origin(first_origin) == step_uri_origin(second_origin)
  end

  def step_uri_origin(value)
    uri = URI(value)
    raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.userinfo.nil?

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
