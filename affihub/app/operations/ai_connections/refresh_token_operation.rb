# frozen_string_literal: true

# Rotates an AIConnection's refresh_token: always overwrites with the NEW refresh_token
# returned by auth.openai.com. On failure (refresh_token already rotated/revoked), marks the
# AIConnection disconnected. See design.md Decision 3/3b.
class AIConnections::RefreshTokenOperation < MainOperation
  # @param params [Hash] :ai_connection (required, the AIConnection to refresh), :provider (optional provider contract)
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @ai_connection = params[:ai_connection]
    @provider = params[:provider] || AIProviders::Resolver.default
  end

  # @return [void]
  def call
    step_refresh_and_persist
  end

  private

  # @return [void]
  def step_refresh_and_persist
    ActiveRecord::Base.transaction do
      connection = AIConnection.lock.find(@ai_connection.id)

      if connection.status_connected? && connection.access_token.present? &&
          token_refresh_not_required?(connection) && connection.access_token_expires_at != @ai_connection.access_token_expires_at
        next
      end

      if connection.status_disconnected? || connection.access_token.blank? || connection.refresh_token.blank?
        connection.update!(status: "disconnected") unless connection.status_disconnected?
        errors.add(:base, "AI connection cần được kết nối lại")
        next
      end

      begin
        tokens = @provider.refresh_token(refresh_token: connection.refresh_token)
      rescue AIProviders::Contract::InvalidCredentialsError
        connection.update!(status: "disconnected")
        errors.add(:base, "AI provider đã từ chối refresh token, cần kết nối lại")
        next
      end

      connection.update!(
        access_token: tokens["access_token"],
        refresh_token: tokens["refresh_token"],
        access_token_expires_at: Time.current + tokens["expires_in"].to_i.seconds,
        status: "connected"
      )
    end
    @ai_connection.reload
  rescue AIProviders::Contract::Error
    errors.add(:base, "Không thể làm mới kết nối AI lúc này. Vui lòng thử lại")
  end

  # Reports whether the locked connection's access token is outside the refresh lead window.
  #
  # @param connection [AIConnection] the freshly locked connection record
  # @return [Boolean] true when the token does not need refresh
  def token_refresh_not_required?(connection)
    connection.access_token_expires_at.present? && connection.access_token_expires_at >= @provider.refresh_lead.from_now
  end
end
