class GoogleConnections::NewService < ApplicationService
  # The integration selected for the OAuth consent step.
  # @return [String, nil]
  attr_reader :integration

  # Reports whether the OAuth client can start an authorization request.
  # @return [Boolean]
  attr_reader :oauth_configured

  # Initializes the Google integration selection screen.
  #
  # @param integration [String, Symbol] the requested Google integration
  # @return [GoogleConnections::NewService] the configured service
  def initialize(integration:)
    @integration = integration.to_s
    super()
  end

  # Validates the chosen integration and loads local OAuth readiness.
  #
  # @return [Boolean] whether the integration can be presented
  def call
    return false unless step_validate_integration
    return false unless step_check_oauth_configuration

    step_succeed!
    success?
  end

  private

  def step_validate_integration
    return true if GoogleConnection::INTEGRATIONS.include?(integration)

    step_fail!("Dịch vụ Google này chưa được hỗ trợ.")
  end

  def step_check_oauth_configuration
    oauth_configuration = Rails.application.config_for(:google).deep_symbolize_keys.fetch(:oauth)
    @oauth_configured = oauth_configuration.fetch(:client_id).present? && oauth_configuration.fetch(:client_secret).present?
    true
  end
end
