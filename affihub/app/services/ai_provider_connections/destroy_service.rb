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

    @remote_revocation_confirmed = if @ai_provider_connection.provider == "openai"
      OpenAi::Client.new.revoke_token(
        refresh_token:,
        client_id: @ai_provider_connection.provider_client_id
      )
    elsif @ai_provider_connection.provider == "gemini"
      Gemini::Client.new.revoke_token(refresh_token:)
    else
      false
    end
  rescue OpenAi::Client::Error, Gemini::Client::Error
    @remote_revocation_confirmed = false
  end

  def step_remove_local_connection
    return true if @ai_provider_connection.destroy

    step_fail!("Không thể xóa thông tin kết nối AI trên máy này.")
  end
end
