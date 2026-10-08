class AiProviderConnections::IndexService < ApplicationService
  PROVIDER_OPTIONS = [
    { key: "chatgpt", provider: "openai", label: "ChatGPT", enabled: true, note: "Tiếp tục bằng tài khoản ChatGPT." },
    { key: "codex", provider: "codex", label: "Codex", enabled: true, note: "Xác thực riêng; quyền tạo nội dung chưa được xác minh." },
    { key: "gemini", label: "Gemini API", enabled: true, note: "Chờ xác minh quyền và hạn mức API." },
    { key: "antigravity", label: "Antigravity", enabled: false, note: "Chưa có quyền tích hợp cho AffiHub." }
  ].freeze

  attr_reader :ai_provider_connections, :provider_options

  # Initializes the provider-account list read action.
  #
  # @param current_origin [String] the browser origin displaying the settings page
  # @return [AiProviderConnections::IndexService] the configured service
  def initialize(current_origin:)
    @current_origin = current_origin
    super()
  end

  # Loads provider accounts and the supported product choices.
  #
  # @return [Boolean] whether the list was loaded
  def call
    return false unless step_load_provider_accounts
    return false unless step_load_provider_options

    step_succeed!
    success?
  end

  private

  def step_load_provider_accounts
    @ai_provider_connections = AiProviderConnection.order(created_at: :desc)
    true
  end

  def step_load_provider_options
    @configuration = Rails.application.config_for(:ai_providers).deep_symbolize_keys
    @provider_options = PROVIDER_OPTIONS.map do |provider_option|
      step_provider_option(provider_option)
    end
    true
  rescue KeyError, URI::InvalidURIError
    step_fail!("Không thể tải cấu hình kết nối tài khoản AI.")
  end

  def step_provider_option(provider_option)
    provider_key = provider_option.fetch(:provider, provider_option.fetch(:key))
    provider_configuration = @configuration.fetch(:providers).fetch(provider_key.to_sym)
    callback_origin = step_callback_origin(provider_configuration)
    provider_option.merge(
      enabled: provider_option.fetch(:enabled) && step_provider_configured?(provider_key, provider_configuration),
      origin_matches: callback_origin.present? && step_same_origin?(callback_origin, @current_origin),
      required_origin: callback_origin
    )
  end

  def step_provider_configured?(provider_key, provider_configuration)
    return false unless provider_configuration.fetch(:enabled)
    return @configuration.fetch(:host_id).present? if provider_key == "openai"
    return provider_configuration.fetch(:client_id).present? if provider_key == "codex"
    return [ :client_id, :client_secret, :project_id ].all? { |key| provider_configuration.fetch(key).present? } if provider_key == "gemini"

    false
  end

  def step_callback_origin(provider_configuration)
    return unless provider_configuration.key?(:redirect_uri)

    step_uri_origin(provider_configuration.fetch(:redirect_uri))
  end

  def step_same_origin?(first_origin, second_origin)
    step_uri_origin(first_origin) == step_uri_origin(second_origin)
  end

  def step_uri_origin(value)
    uri = URI(value)
    raise URI::InvalidURIError unless uri.is_a?(URI::HTTP) && uri.userinfo.nil?

    "#{uri.scheme}://#{uri.host}:#{uri.port}"
  end
end
