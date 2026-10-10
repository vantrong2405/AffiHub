class GoogleConnections::IndexService < ApplicationService
  # The saved optional Google integrations shown in settings.
  # @return [ActiveRecord::Relation<GoogleConnection>]
  attr_reader :google_connections

  # Reports whether the encrypted OAuth client credentials are configured.
  # @return [Boolean]
  attr_reader :oauth_configured

  # Reports whether the settings page has any saved Google account.
  # @return [Boolean]
  attr_reader :has_google_connections

  # Initializes the optional Google integration index.
  #
  # @return [GoogleConnections::IndexService] the configured service
  def initialize
    super()
  end

  # Loads saved account connections and checks local OAuth configuration.
  #
  # @return [Boolean] whether settings data was loaded
  def call
    return false unless step_load_google_connections
    return false unless step_check_oauth_configuration

    step_succeed!
    success?
  end

  private

  def step_load_google_connections
    @google_connections = GoogleConnection.order(integration: :asc, created_at: :desc).to_a
    @has_google_connections = google_connections.any?
    true
  end

  def step_check_oauth_configuration
    oauth_configuration = Rails.application.config_for(:google).deep_symbolize_keys.fetch(:oauth)
    @oauth_configured = oauth_configuration.fetch(:client_id).present? && oauth_configuration.fetch(:client_secret).present?
    true
  end
end
