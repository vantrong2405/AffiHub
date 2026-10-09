module ApplicationHelper
  include GoogleIntegrationsHelper

  SOCIAL_PROVIDER_NAMES = {
    "facebook" => "Facebook",
    "instagram" => "Instagram",
    "tiktok" => "TikTok",
    "youtube" => "YouTube"
  }.freeze

  PREFLIGHT_STATUS_LABELS = {
    passed: "Đạt",
    warning: "Cảnh báo",
    blocked: "Chặn",
    unavailable: "Chưa thể kiểm tra",
    not_configured: "Chưa cấu hình"
  }.freeze

  # Returns the product label for a configured social provider.
  #
  # @param provider [String, Symbol] the configured social provider key
  # @return [String] the provider's user-facing product name
  def social_provider_name(provider)
    SOCIAL_PROVIDER_NAMES.fetch(provider.to_s, provider.to_s.humanize)
  end

  # Returns the destination noun displayed for a connected social provider.
  #
  # @param provider [String, Symbol] the connected social provider key
  # @return [String] the destination label
  def social_destination_name(provider)
    case provider.to_s
    when "youtube" then "kênh"
    when "tiktok" then "tài khoản TikTok"
    else "Page"
    end
  end

  # Reports whether the provider uses the destination selection screen.
  #
  # @param provider [String, Symbol] the connected social provider key
  # @return [Boolean] whether destinations can be selected after connection
  def social_destination_selection_supported?(provider)
    %w[facebook instagram youtube].include?(provider.to_s)
  end

  # Returns the Vietnamese label for a preflight readiness status.
  #
  # @param status [String, Symbol] the saved or aggregate readiness status
  # @return [String] the user-facing status label
  def preflight_status_label(status)
    status_key = preflight_status_key(status)
    return status.to_s if status_key.nil?

    PREFLIGHT_STATUS_LABELS.fetch(status_key)
  end

  # Returns the daisyUI badge tone for a preflight readiness status.
  #
  # @param status [String, Symbol] the saved or aggregate readiness status
  # @return [String] the daisyUI badge class
  def preflight_status_badge_class(status)
    case preflight_status_key(status)
    when :passed then "badge-success"
    when :warning, :unavailable then "badge-warning"
    when :blocked then "badge-error"
    when :not_configured then "badge-ghost"
    else "badge-ghost"
    end
  end

  private

  def preflight_status_key(status)
    normalized_status = status.to_s
    return :passed if normalized_status == "ready"

    status_key = normalized_status.to_sym
    PREFLIGHT_STATUS_LABELS.key?(status_key) ? status_key : nil
  end
end
