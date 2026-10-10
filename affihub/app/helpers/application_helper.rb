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

  PREFLIGHT_CHECK_TITLES = {
    "connector" => "Kết nối tài khoản",
    "media_transfer" => "Chuyển file media",
    "content_policy" => "Chính sách nội dung",
    "publishing_cap" => "Giới hạn đăng",
    "permissions" => "Quyền đăng lên Page",
    "quota" => "Quota YouTube"
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
    return "Đạt kỹ thuật" if status.to_s == "ready"

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

  # Returns counts for each technical destination result shown in a preflight report.
  #
  # @param destination_entries [Enumerable<Hash>] the report's destination entries
  # @return [Hash{Symbol => Integer}] counts keyed by the technical readiness status
  def preflight_destination_counts(destination_entries)
    counts = { ready: 0, blocked: 0, unavailable: 0 }
    destination_entries.each do |entry|
      status = entry.fetch(:status).to_sym
      counts[status] += 1 if counts.key?(status)
    end
    counts
  end

  # Returns select options for the destination filter on a preflight report.
  #
  # @param destination_entries [Enumerable<Hash>] the report's destination entries
  # @return [Array<Array<String, Integer>>] option labels and destination IDs
  def preflight_destination_options(destination_entries)
    destination_entries.map do |entry|
      provider = entry[:provider]
      label = provider.present? ? "#{entry.fetch(:name)} · #{social_provider_name(provider)}" : entry.fetch(:name)
      [ label, entry.fetch(:id) ]
    end
  end

  # Returns the display title for one preflight check card.
  #
  # @param check_key [String] the saved check identifier
  # @param check [Hash] the saved check result
  # @return [String] the Vietnamese check title
  def preflight_check_title(check_key, check)
    PREFLIGHT_CHECK_TITLES.fetch(check_key.to_s) { check.fetch("subject", "Kiểm tra") }
  end

  # Reports whether a preflight check should show a corrective action link.
  #
  # @param remediation_path [String, nil] the relevant correction screen path
  # @param status [String] the saved preflight check status
  # @return [Boolean] whether the link should be rendered
  def preflight_remediation_available?(remediation_path, status)
    remediation_path.present? && preflight_status_key(status) != :passed
  end

  # Returns the remediation path for a preflight check when a related screen exists.
  #
  # @param check_key [String] the saved check identifier
  # @param video_project [VideoProject] the project under review
  # @param render_version [RenderVersion] the render under review
  # @param social_connection_id [Integer, nil] the destination's connection ID
  # @return [String, nil] a path for the relevant correction screen
  def preflight_remediation_path(check_key, video_project:, render_version:, social_connection_id:)
    case check_key.to_s
    when "source"
      video_project_source_assets_path(video_project)
    when "render"
      new_video_project_render_version_path(video_project, source_asset_id: render_version.source_asset_id)
    when "connector"
      social_connection_path(social_connection_id) if social_connection_id
    when "permissions"
      social_connection_social_destinations_path(social_connection_id) if social_connection_id
    when "content_policy"
      new_video_project_render_version_path(video_project, source_asset_id: render_version.source_asset_id)
    when "google_drive", "google_sheets"
      google_connections_path
    end
  end

  # Returns a Vietnamese label for an external production gate status.
  #
  # @param status [String] the saved production gate status
  # @return [String] the gate status label
  def preflight_production_gate_status_label(status)
    case status.to_s
    when "public_restricted" then "Đăng công khai bị giới hạn"
    when "audited_in_configuration" then "Cấu hình ghi nhận đã audit"
    when "not_verified" then "Chưa xác minh"
    else status.to_s.humanize
    end
  end

  # Returns the daisyUI badge tone for an external production gate status.
  #
  # @param status [String] the saved production gate status
  # @return [String] the daisyUI badge class
  def preflight_production_gate_badge_class(status)
    case status.to_s
    when "public_restricted", "not_verified" then "badge-warning"
    when "audited_in_configuration" then "badge-info"
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
