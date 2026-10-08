class AiProviderConnections::AccessTokenService < ApplicationService
  attr_reader :access_token

  # Initializes access-token retrieval for a connected AI account.
  #
  # @param ai_provider_connection_id [String, Integer] the connected account ID
  # @return [AiProviderConnections::AccessTokenService] the configured service
  def initialize(ai_provider_connection_id:)
    @ai_provider_connection_id = ai_provider_connection_id
    super()
  end

  # Returns a valid access token and serializes refreshes for the same account.
  #
  # @return [Boolean] whether a usable access token was returned
  def call
    return false unless step_load_connection
    return false unless step_validate_connection

    step_load_access_token
    success?
  end

  private

  def step_load_connection
    @ai_provider_connection = AiProviderConnection.find_by(id: @ai_provider_connection_id)
    return true if @ai_provider_connection

    step_fail!("Không tìm thấy kết nối tài khoản AI.")
  end

  def step_validate_connection
    return step_fail!("Gemini API đang chờ xác minh trước khi sử dụng.") if @ai_provider_connection.provider == "gemini"
    return step_fail!("Nhà cung cấp này chưa hỗ trợ tạo nội dung.") unless @ai_provider_connection.provider == "openai"
    return step_fail!("Kết nối AI chưa sẵn sàng sử dụng.") unless @ai_provider_connection.ready?
    return step_fail!("Tài khoản AI chưa chọn model hợp lệ.") if @ai_provider_connection.selected_model.blank?

    true
  end

  def step_load_access_token
    configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    provider_configuration = configuration.fetch(:providers).fetch(:openai)
    @ai_provider_connection.with_lock do
      if step_token_expiring?(configuration.fetch(:token_refresh_buffer_seconds))
        step_refresh_access_token(provider_configuration)
      else
        @access_token = @ai_provider_connection.access_token
        step_succeed!
      end
    end
    success?
  rescue ActiveRecord::RecordNotFound, KeyError
    step_fail!("Không thể tải cấu hình token của tài khoản AI.")
  end

  def step_token_expiring?(buffer_seconds)
    expiry = @ai_provider_connection.access_token_expires_at
    expiry.present? && expiry <= Time.current + buffer_seconds.seconds
  end

  def step_refresh_access_token(provider_configuration)
    if @ai_provider_connection.refresh_token.blank?
      return step_mark_reauthorization_required
    end

    client = OpenAi::Client.new(configuration: provider_configuration)
    response = client.refresh_token(
      refresh_token: @ai_provider_connection.refresh_token,
      client_id: @ai_provider_connection.provider_client_id
    )
    return step_fail!("Provider không trả access token mới.") if response["access_token"].blank?

    @ai_provider_connection.assign_attributes(
      access_token: response.fetch("access_token"),
      refresh_token: response["refresh_token"].presence || @ai_provider_connection.refresh_token,
      access_token_expires_at: step_token_expiry(response["expires_in"]),
      scopes: response["scope"].present? ? response["scope"].split.uniq : @ai_provider_connection.scopes
    )
    if (provider_configuration.fetch(:required_scopes) - @ai_provider_connection.scopes).any?
      @ai_provider_connection.status = :scope_missing
      @ai_provider_connection.save!
      return step_fail!("Tài khoản AI không còn quyền sử dụng model.")
    end

    @ai_provider_connection.save!
    @access_token = @ai_provider_connection.access_token
    step_succeed!
  rescue OpenAi::Client::Error => error
    return step_mark_reauthorization_required if error.code == "invalid_grant"

    step_fail!("Không thể làm mới token của tài khoản AI.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu token mới của tài khoản AI.")
  end

  def step_token_expiry(expires_in)
    seconds = expires_in.to_i
    seconds.positive? ? Time.current + seconds.seconds : nil
  end

  def step_mark_reauthorization_required
    @ai_provider_connection.update!(status: :reauth_required)
    step_fail!("Tài khoản AI cần đăng nhập lại.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Tài khoản AI cần đăng nhập lại.")
  end
end
