# frozen_string_literal: true

class SocialConnections::ConnectOperation < MainOperation
  attr_reader :social_connection

  # @param params [Hash] :current_user, :code, and :redirect_uri
  # @param client [MetaGraphClient] Meta API boundary
  # @return [void]
  def initialize(params:, client: MetaGraphClient.new)
    super(params:)
    @errors = ActiveModel::Errors.new(self)
    @code = params[:code]
    @redirect_uri = params[:redirect_uri]
    @client = client
  end

  # Exchanges the OAuth code and persists only the long-lived user token.
  #
  # @return [void]
  def call
    step_exchange_short_lived_token
    return if error?

    step_exchange_long_lived_token
    step_save_connection unless error?
  end

  private

  # Exchanges the authorization code for a short-lived access token.
  #
  # @return [void]
  def step_exchange_short_lived_token
    @short_lived_token = @client.exchange_token(code: @code, redirect_uri: @redirect_uri).fetch("access_token")
  rescue MetaGraphClient::ApiError, KeyError
    errors.add(:base, "Không thể hoàn tất xác thực Facebook. Vui lòng thử kết nối lại.")
  rescue MetaGraphClient::TransportError
    errors.add(:base, "Không thể kết nối Meta lúc này. Vui lòng thử lại.")
  end

  # Converts the temporary token into a long-lived user token before persistence.
  #
  # @return [void]
  def step_exchange_long_lived_token
    @long_lived_token = @client.exchange_long_lived_token(access_token: @short_lived_token).fetch("access_token")
  rescue MetaGraphClient::ApiError, KeyError
    errors.add(:base, "Không thể gia hạn Facebook access token. Hãy kết nối lại.")
  rescue MetaGraphClient::TransportError
    errors.add(:base, "Không thể kết nối Meta lúc này. Vui lòng thử lại.")
  end

  # Saves the long-lived token only after both provider exchanges succeed.
  #
  # @return [void]
  def step_save_connection
    @social_connection = current_user.social_connection || current_user.build_social_connection(provider: "facebook")
    @social_connection.assign_attributes(provider: "facebook", access_token: @long_lived_token)
    errors.merge!(@social_connection.errors) unless @social_connection.save
  end
end
