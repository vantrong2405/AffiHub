class SocialConnections::TikTok::AccessTokenService < ApplicationService
  attr_reader :access_token

  # Initializes token retrieval for one connected TikTok creator destination.
  #
  # @param social_destination_id [Integer] the TikTok destination to publish to
  # @return [SocialConnections::TikTok::AccessTokenService] the configured service
  def initialize(social_destination_id:)
    @social_destination_id = social_destination_id
    super()
  end

  # Returns a usable creator token, refreshing and rotating it before expiry.
  #
  # @return [Boolean] whether a valid TikTok token was loaded
  def call
    return false unless step_load_destination
    return false unless step_validate_connection

    step_load_access_token
    success?
  end

  private

  def step_load_destination
    @social_destination = SocialDestination.includes(:social_connection).find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích đăng TikTok.") unless @social_destination
    return step_fail!("Đích đăng này không phải tài khoản TikTok.") unless @social_destination.provider == "tiktok"

    @social_connection = @social_destination.social_connection
    true
  end

  def step_validate_connection
    return step_fail!("Kết nối TikTok chưa hoạt động.") unless @social_connection.connected?
    return step_fail!("Đích đăng TikTok chưa hoạt động.") unless @social_destination.connected?
    return step_fail!("TikTok chưa cấp access token cho đích đăng.") if @social_destination.access_token.blank?

    true
  end

  def step_load_access_token
    @social_connection.with_lock do
      @social_destination = @social_connection.social_destinations.find(@social_destination_id)
      if step_token_expiring?
        step_refresh_access_token
      else
        @access_token = @social_destination.access_token
        step_succeed!
      end
    end
    success?
  rescue ActiveRecord::RecordNotFound
    step_fail!("Không tìm thấy đích đăng TikTok.")
  end

  def step_token_expiring?
    expiry = @social_connection.token_expires_at || @social_destination.token_expires_at
    return false unless expiry

    buffer_seconds = tiktok_configuration.fetch(:token_refresh_buffer_seconds).to_i
    expiry <= Time.current + buffer_seconds.seconds
  end

  def step_refresh_access_token
    return step_mark_reauthorization_required if refresh_token_unavailable?

    response = TikTok::Client.new.refresh_token(refresh_token: @social_connection.refresh_token)
    return step_fail!("TikTok không trả access token mới.") if response["access_token"].blank?

    next_scopes = if response["scope"].present?
      response.fetch("scope").split(",").map(&:strip).reject(&:blank?).uniq
    else
      @social_connection.scopes
    end
    required_scopes = tiktok_configuration.fetch(:required_publish_scopes)
    return step_mark_reauthorization_required if (required_scopes - next_scopes).any?

    step_persist_refreshed_tokens(response, next_scopes)
  rescue TikTok::Client::Error => error
    return step_mark_reauthorization_required if error.code == "invalid_grant"

    step_fail!("Không thể làm mới token TikTok.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu token TikTok mới.")
  end

  def step_persist_refreshed_tokens(response, next_scopes)
    access_token_expiry = step_expiry(response["expires_in"])
    refresh_token_expiry = step_expiry(response["refresh_expires_in"]) || @social_connection.refresh_token_expires_at
    @social_connection.update!(
      access_token: response.fetch("access_token"),
      refresh_token: response["refresh_token"].presence || @social_connection.refresh_token,
      token_expires_at: access_token_expiry,
      refresh_token_expires_at: refresh_token_expiry,
      scopes: next_scopes,
      status: :connected
    )
    @social_connection.social_destinations.each do |destination|
      destination.update!(
        access_token: @social_connection.access_token,
        token_expires_at: access_token_expiry,
        status: :connected
      )
    end
    @social_destination = @social_connection.social_destinations.find(@social_destination_id)
    @access_token = @social_destination.access_token
    step_succeed!
  end

  def refresh_token_unavailable?
    refresh_token_expiry = @social_connection.refresh_token_expires_at
    @social_connection.refresh_token.blank? || (refresh_token_expiry && refresh_token_expiry <= Time.current)
  end

  def step_mark_reauthorization_required
    @social_connection.update!(status: :reauth_required)
    @social_connection.social_destinations.each { |destination| destination.update!(status: :reauth_required) }
    step_fail!("Tài khoản TikTok cần kết nối lại.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Tài khoản TikTok cần kết nối lại.")
  end

  def step_expiry(expires_in)
    seconds = expires_in.to_i
    seconds.positive? ? Time.current + seconds.seconds : nil
  end

  def tiktok_configuration
    SocialConnections::ProviderConfiguration.for(:tiktok)
  end
end
