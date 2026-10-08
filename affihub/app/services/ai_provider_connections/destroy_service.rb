class AiProviderConnections::DestroyService < ApplicationService
  attr_reader :remote_revocation_confirmed

  # Initializes a local provider-connection removal.
  #
  # @param ai_provider_connection_id [String, Integer] the account to disconnect
  # @return [AiProviderConnections::DestroyService] the configured service
  def initialize(ai_provider_connection_id:)
    @ai_provider_connection_id = ai_provider_connection_id
    @remote_revocation_confirmed = false
    super()
  end

  # Revokes the renewable provider session when possible and removes local tokens.
  #
  # @return [Boolean] whether the local connection was removed
  def call
    return false unless step_load_connection
    step_revoke_provider_session
    return false unless step_remove_local_connection

    step_succeed!
    success?
  end

  private

  def step_load_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
    return true if @ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI.")
  end

  def step_revoke_provider_session
    refresh_token = @ai_provider_connection.refresh_token
    return if refresh_token.blank?
    return unless step_load_provider_configuration
    return unless @provider_configuration.fetch(:revocation_enabled, false)

    client_class = @provider_configuration.fetch(:clients).fetch(:revocation).constantize
    client = client_class.new(configuration: @provider_configuration)
    revocation_arguments = { refresh_token: }
    @provider_configuration.fetch(:revocation_arguments, []).each do |argument|
      revocation_arguments[argument.to_sym] = @ai_provider_connection.provider_client_id
    end
    @remote_revocation_confirmed = client.revoke_token(**revocation_arguments)
  rescue AiProviderClientError, KeyError
    @remote_revocation_confirmed = false
  end

  def step_load_provider_configuration
    configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    @provider_configuration = configuration.fetch(:providers).fetch(@ai_provider_connection.provider.to_sym)
    true
  rescue KeyError
    false
  end

  def step_remove_local_connection
    return true if @ai_provider_connection.destroy

    step_fail!("Không thể xóa thông tin kết nối AI trên máy này.")
  end
end
