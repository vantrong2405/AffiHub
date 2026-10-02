# frozen_string_literal: true

class AIConnection < ApplicationRecord
  class DisconnectedError < StandardError; end

  belongs_to :user

  encrypts :access_token, :refresh_token, :id_token

  enum :status, { disconnected: "disconnected", connected: "connected" }, prefix: true

  validates :user_id, uniqueness: true

  # Confirms this connection has the credentials required for the selected provider.
  #
  # @param provider [AIProviders::Contract] provider whose refresh policy applies
  # @return [void]
  # @raise [AIConnection::DisconnectedError] when the connection lacks usable credentials
  def ensure_usable!(provider: AIProviders::Resolver.default)
    return if status_connected? && access_token.present? && (token_refresh_not_required?(provider) || refresh_token.present?)

    update!(status: "disconnected") unless status_disconnected?
    raise DisconnectedError, "AI connection cần được kết nối lại"
  end

  # Refreshes the access token before a provider request when it is expired or near expiry.
  #
  # @param provider [AIProviders::Contract] provider used for refresh and its lead-time policy
  # @return [void]
  # @raise [AIConnection::DisconnectedError] when the connection cannot be refreshed
  def ensure_fresh_token!(provider: AIProviders::Resolver.default)
    ensure_usable!(provider:)
    return if token_refresh_not_required?(provider)

    result = AIConnections::RefreshTokenOperation.call(params: { ai_connection: self, provider: provider })
    raise DisconnectedError, "refresh thất bại, AIConnection đã disconnected" unless result.success?
  end

  private

  # @param provider [AIProviders::Contract] provider whose refresh lead applies
  # @return [Boolean] whether the current access token is outside the provider refresh window
  def token_refresh_not_required?(provider)
    access_token_expires_at.present? && access_token_expires_at >= provider.refresh_lead.from_now
  end
end
