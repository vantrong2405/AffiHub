class AiProviderConnections::ShowService < ApplicationService
  attr_reader :ai_provider_connection, :callback_origin, :callback_origin_matches

  # Initializes a provider-account read action.
  #
  # @param ai_provider_connection_id [String, Integer] the account ID to show
  # @param current_origin [String, nil] the browser origin displaying the account
  # @return [AiProviderConnections::ShowService] the configured service
  def initialize(ai_provider_connection_id:, current_origin: nil)
    @ai_provider_connection_id = ai_provider_connection_id
    @current_origin = current_origin
    super()
  end

  # Loads one provider account for the details page.
  #
  # @return [Boolean] whether the requested account was found
  def call
    return false unless step_load_connection
    return false unless step_load_callback_origin

    step_succeed!
    success?
  end

  private

  def step_load_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
    return true if @ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI.")
  end

  def step_load_callback_origin
    configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    provider_configuration = configuration.fetch(:providers).fetch(@ai_provider_connection.provider.to_sym)
    redirect_uri = provider_configuration.fetch(:redirect_uri)
    @callback_origin = step_uri_origin(redirect_uri)
    @callback_origin_matches = @current_origin.present? && step_uri_origin(@current_origin) == @callback_origin
    true
  rescue KeyError, URI::InvalidURIError
    step_fail!("Không thể tải cấu hình callback cho tài khoản AI.")
  end

  def step_uri_origin(value)
    uri = URI(value)
    raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.userinfo.nil?

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
