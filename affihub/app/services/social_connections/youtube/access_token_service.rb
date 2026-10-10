class SocialConnections::Youtube::AccessTokenService < ApplicationService
  attr_reader :access_token

  # Initializes access-token retrieval for a connected YouTube channel.
  #
  # @param social_destination_id [Integer] the YouTube channel destination
  # @return [SocialConnections::Youtube::AccessTokenService] the configured service
  def initialize(social_destination_id:)
    @social_destination_id = social_destination_id
    @configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:oauth)
    super()
  end

  # Returns a usable channel token, refreshing it when it is close to expiry.
  #
  # @return [Boolean] whether a valid access token was loaded
  def call
    return false unless step_load_destination
    return false unless step_validate_connection

    step_load_access_token
    success?
  end

  private

  def step_load_destination
    @social_destination = SocialDestination.includes(:social_connection).find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích đăng YouTube.") unless @social_destination
    return step_fail!("Đích đăng này không phải kênh YouTube.") unless @social_destination.provider == "youtube"

    @social_connection = @social_destination.social_connection
    true
  end

  def step_validate_connection
    return step_fail!("Kết nối YouTube chưa hoạt động.") unless @social_connection.connected?
    return step_fail!("Kênh YouTube chưa hoạt động.") unless @social_destination.connected?
    return step_fail!("YouTube chưa cấp access token cho kênh này.") if @social_destination.access_token.blank?

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
    step_fail!("Không tìm thấy đích đăng YouTube.")
  end

  def step_token_expiring?
    expiry = @social_connection.token_expires_at || @social_destination.token_expires_at
    return false unless expiry

    expiry <= Time.current + @configuration.fetch(:token_refresh_buffer_seconds).to_i.seconds
  end

  def step_refresh_access_token
    return step_mark_reauthorization_required if refresh_token_unavailable?

    response = Youtube::Client.new.refresh_token(refresh_token: @social_connection.refresh_token)
    return step_fail!("Google không trả access token mới cho YouTube.") if response["access_token"].blank?

    next_scopes = if response["scope"].present?
      response.fetch("scope").split(/[ ,]+/).map(&:strip).reject(&:blank?).uniq
    else
      @social_connection.scopes
    end
    return step_mark_reauthorization_required if (required_publish_scopes - next_scopes).any?

    step_persist_refreshed_tokens(response, next_scopes)
  rescue Youtube::Client::Error => error
    return step_mark_reauthorization_required if error.code == "invalid_grant"

    step_fail!("Không thể làm mới access token YouTube.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu access token YouTube mới.")
  end

  def step_persist_refreshed_tokens(response, scopes)
    access_token_expiry = step_expiry(response["expires_in"])
    refresh_token_expiry = step_expiry(response["refresh_token_expires_in"]) || @social_connection.refresh_token_expires_at
    @social_connection.update!(
      access_token: response.fetch("access_token"),
      refresh_token: response["refresh_token"].presence || @social_connection.refresh_token,
      token_expires_at: access_token_expiry,
      refresh_token_expires_at: refresh_token_expiry,
      scopes:,
      status: :connected
    )
    @social_connection.social_destinations.each do |social_destination|
      social_destination.update!(access_token: @social_connection.access_token, token_expires_at: access_token_expiry)
    end
    @social_destination = @social_connection.social_destinations.find(@social_destination_id)
    @access_token = @social_destination.access_token
    step_succeed!
  end

  def refresh_token_unavailable?
    refresh_expiry = @social_connection.refresh_token_expires_at
    @social_connection.refresh_token.blank? || (refresh_expiry && refresh_expiry <= Time.current)
  end

  def required_publish_scopes
    @configuration.fetch(:required_publish_scopes)
  end

  def step_mark_reauthorization_required
    @social_connection.update!(status: :reauth_required)
    @social_connection.social_destinations.each do |social_destination|
      social_destination.update!(status: :reauth_required)
    end
    step_fail!("Tài khoản YouTube cần kết nối lại để tiếp tục đăng.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Tài khoản YouTube cần kết nối lại để tiếp tục đăng.")
  end

  def step_expiry(expires_in)
    seconds = expires_in.to_i
    seconds.positive? ? Time.current + seconds.seconds : nil
  end
end
