module AiProviderConnectionsHelper
  # Returns the Vietnamese copy used by an AI provider account screen.
  #
  # @param provider [String, Symbol] the connected provider key
  # @param display_name [String] the provider display name from configuration
  # @return [Hash] the copy for the provider account views
  def ai_provider_copy(provider:, display_name:)
    copy = case provider.to_s
    when "codex"
      {
        option_note: "Xác thực riêng; quyền tạo nội dung chưa được xác minh.",
        account_summary: {
          connected: "Đã xác thực tài khoản; quyền model và quota chưa được xác minh.",
          scope_missing: "Tài khoản chưa cấp quyền bắt buộc."
        },
        account_action_label: "Xem xác thực",
        pending_verification: {
          heading: "Kết nối đã lưu, inference chưa được bật",
          detail: "#{display_name} mới xác nhận đăng nhập. AffiHub chưa xác minh contract inference hoặc quota và không gửi yêu cầu model."
        },
        scope_missing: {
          heading: "Tài khoản chưa cấp quyền dùng model",
          detail: "Tài khoản chưa cấp đủ quyền bắt buộc để hoàn tất kết nối."
        },
        permissions: {
          granted: "Đăng nhập #{display_name} đã hoàn tất; quyền dùng model chưa được xác minh.",
          missing: "Tài khoản chưa cấp đủ quyền bắt buộc.",
          detail: "Không có model list/quota hiển thị và chưa thể tạo nội dung bằng kết nối này."
        },
        model_catalog: {
          heading: "Model #{display_name}",
          detail: "Chưa tải model list vì AffiHub chỉ xác minh đăng nhập Codex và chưa bật inference.",
          empty: "Chưa có danh sách model được xác minh."
        }
      }
    when "gemini"
      {
        option_note: "Chờ xác minh quyền và hạn mức API.",
        account_summary: {
          connected: "Inference vẫn bị khóa đến khi giới hạn sử dụng và chi phí theo model được kiểm tra.",
          scope_missing: "Tài khoản chưa cấp scope #{display_name} cần thiết."
        },
        account_action_label: "Quản lý model",
        pending_verification: {
          heading: "Kết nối đã lưu, inference chưa được bật",
          detail: "AffiHub giữ inference ở trạng thái chờ xác minh đến khi giới hạn sử dụng và chi phí theo model được kiểm tra cho project này."
        },
        scope_missing: {
          heading: "Tài khoản chưa cấp quyền dùng model",
          detail: "Tài khoản Google chưa cấp scope #{display_name} cần thiết. Đăng nhập lại và cấp quyền trước khi dùng model."
        },
        permissions: {
          granted: "OAuth #{display_name} đã cấp quyền đọc model.",
          missing: "OAuth chưa cấp quyền #{display_name} cần thiết.",
          detail: "Xem quota theo project và bảng giá Gemini API chính thức trước khi bật inference."
        },
        model_catalog: {
          heading: "Model của tài khoản",
          detail: "Chỉ model do chính tài khoản provider trả về mới được lưu lựa chọn.",
          empty: "Provider chưa trả model nào có thể chọn cho tài khoản này."
        }
      }
    when "antigravity"
      {
        option_note: "Chưa có quyền tích hợp cho AffiHub.",
        account_summary: {
          connected: "Quyền sử dụng tài khoản này chưa được xác minh.",
          scope_missing: "Tài khoản chưa cấp đủ quyền bắt buộc."
        },
        account_action_label: "Xem kết nối",
        pending_verification: {
          heading: "Kết nối đang chờ xác minh",
          detail: "Quyền truy cập và khả năng tạo nội dung chưa được xác minh."
        },
        scope_missing: {
          heading: "Tài khoản chưa cấp quyền dùng model",
          detail: "Tài khoản chưa cấp đủ quyền bắt buộc để hoàn tất kết nối."
        },
        permissions: {
          granted: "Quyền sử dụng chưa được xác minh.",
          missing: "Tài khoản chưa cấp đủ quyền bắt buộc.",
          detail: "Khả năng tạo nội dung chưa được xác minh."
        },
        model_catalog: {
          heading: "Model của tài khoản",
          detail: "Danh sách model chưa được xác minh.",
          empty: "Chưa có danh sách model được xác minh."
        }
      }
    else
      raise ArgumentError, "Unsupported AI provider: #{provider}"
    end

    copy.merge(connect_button_label: "Kết nối #{display_name}")
  end

  # Prepares provider option labels, status, and OAuth actions for the account list.
  #
  # @param provider_options [Array<Hash>] provider choices prepared by the index Service
  # @return [Array<Hash>] view-ready provider choice presentation
  def ai_provider_options_presentation(provider_options:)
    provider_options.map do |provider_option|
      provider_copy = ai_provider_copy(
        provider: provider_option.fetch(:provider),
        display_name: provider_option.fetch(:label)
      )
      {
        label: provider_option.fetch(:label),
        availability_label: provider_option.fetch(:enabled) ? "Có thể kết nối" : "Chưa khả dụng",
        note: provider_copy.fetch(:option_note),
        action: ai_provider_option_action(provider_option:, provider_copy:)
      }
    end
  end

  # Prepares connected account labels and navigation for the account list.
  #
  # @param connections [Array<AiProviderConnection>] saved provider connections
  # @param provider_presentations [Hash] safe provider presentation settings keyed by provider
  # @return [Array<Hash>] view-ready connected account presentation
  def ai_provider_accounts_presentation(connections:, provider_presentations:)
    accounts = connections.map do |connection|
      provider_presentation = provider_presentations.fetch(connection.provider.to_sym)
      provider_name = provider_presentation.fetch(:display_name)
      provider_copy = ai_provider_copy(provider: connection.provider, display_name: provider_name)
      summary_key = connection.scope_missing? ? :scope_missing : :connected
      account_email = connection.account_email

      {
        account_name: connection.display_name.presence || account_email,
        account_label: account_email.present? ? "#{provider_name} · #{account_email}" : provider_name,
        status: connection.status,
        summary: provider_copy.fetch(:account_summary).fetch(summary_key),
        action_label: provider_copy.fetch(:account_action_label),
        path: ai_provider_connection_path(connection)
      }
    end

    {
      accounts:,
      has_accounts: accounts.any?,
      empty_state: {
        heading: "Chưa có tài khoản AI nào",
        detail: "Chọn một nhà cung cấp khả dụng ở phía trên để kết nối tài khoản."
      }
    }
  end

  # Prepares all dynamic account details for the provider connection screen.
  #
  # @param connection [AiProviderConnection] the connected provider account
  # @param provider_presentation [Hash] safe provider settings prepared by the show Service
  # @param callback_origin [String] the provider callback origin
  # @param callback_origin_matches [Boolean] whether the current page uses that origin
  # @return [Hash] view-ready account status, permissions, models, and actions
  def ai_provider_connection_presentation(
    connection:,
    provider_presentation:,
    callback_origin:,
    callback_origin_matches:
  )
    provider_name = provider_presentation.fetch(:display_name)
    provider_copy = ai_provider_copy(provider: connection.provider, display_name: provider_name)
    required_scopes = Array(provider_presentation.fetch(:required_scopes))
    permission_copy = provider_copy.fetch(:permissions)
    model_catalog_copy = provider_copy.fetch(:model_catalog)
    model_options = Array(connection.available_models).map do |model|
      [ model.fetch("display_name"), model.fetch("slug") ]
    end

    {
      account_name: connection.display_name.presence || connection.account_email,
      provider_name:,
      status: connection.status,
      status_notice: ai_provider_connection_status_notice(connection:, provider_copy:),
      permissions: {
        message: (required_scopes - Array(connection.scopes)).empty? ? permission_copy.fetch(:granted) : permission_copy.fetch(:missing),
        detail: permission_copy.fetch(:detail)
      },
      last_verified_label: connection.last_verified_at ? l(connection.last_verified_at, format: :short) : "Chưa có",
      quota_and_pricing_sources: ai_provider_connection_sources(provider_presentation:),
      model_catalog: {
        enabled: provider_presentation.fetch(:model_selection_enabled),
        has_options: model_options.any?,
        heading: model_catalog_copy.fetch(:heading),
        detail: model_catalog_copy.fetch(:detail),
        empty: model_catalog_copy.fetch(:empty),
        options: model_options,
        selected_model: connection.selected_model
      },
      management_action: ai_provider_connection_management_action(
        connection:,
        callback_origin:,
        callback_origin_matches:
      )
    }
  end

  private

  def ai_provider_option_action(provider_option:, provider_copy:)
    return { kind: :disabled, label: "Chưa khả dụng" } unless provider_option.fetch(:enabled)
    return {
      kind: :button,
      label: provider_copy.fetch(:connect_button_label),
      path: ai_provider_connections_path,
      params: { provider: provider_option.fetch(:provider) }
    } if provider_option.fetch(:origin_matches)

    required_origin = provider_option.fetch(:required_origin)
    {
      kind: :link,
      label: "Mở AffiHub",
      href: "#{required_origin}#{ai_provider_connections_path}",
      callback_origin: required_origin
    }
  end

  def ai_provider_connection_status_notice(connection:, provider_copy:)
    return {
      class_name: "alert alert-warning",
      role: "status",
      heading: provider_copy.fetch(:pending_verification).fetch(:heading),
      detail: provider_copy.fetch(:pending_verification).fetch(:detail)
    } if connection.pending_verification?
    return {
      class_name: "alert alert-warning",
      role: "status",
      heading: provider_copy.fetch(:scope_missing).fetch(:heading),
      detail: provider_copy.fetch(:scope_missing).fetch(:detail)
    } if connection.scope_missing?
    return {
      class_name: "alert alert-error",
      role: "alert",
      heading: "Cần đăng nhập lại",
      detail: "Token hiện tại không còn được provider chấp nhận."
    } if connection.reauth_required?

    nil
  end

  def ai_provider_connection_management_action(connection:, callback_origin:, callback_origin_matches:)
    return unless connection.scope_missing? || connection.reauth_required?
    return {
      kind: :button,
      label: "Đăng nhập lại",
      path: ai_provider_connections_path,
      params: { provider: connection.provider, ai_provider_connection_id: connection.id }
    } if callback_origin_matches

    {
      kind: :link,
      label: "Mở AffiHub",
      href: "#{callback_origin}#{ai_provider_connection_path(connection)}",
      callback_origin:
    }
  end

  def ai_provider_connection_sources(provider_presentation:)
    project_id = provider_presentation[:project_id]
    quota_console_url = provider_presentation[:quota_console_url]
    pricing_source_url = provider_presentation[:pricing_source_url]
    return if [ project_id, quota_console_url, pricing_source_url ].any?(&:blank?)

    {
      project_id:,
      quota_url: "#{quota_console_url}?#{URI.encode_www_form(project: project_id)}",
      pricing_url: pricing_source_url
    }
  end
end
