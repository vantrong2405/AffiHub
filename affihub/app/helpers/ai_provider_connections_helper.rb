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
          connected: "Inference, quota và giá của project vẫn đang chờ xác minh.",
          scope_missing: "Tài khoản chưa cấp scope #{display_name} cần thiết."
        },
        account_action_label: "Quản lý model",
        pending_verification: {
          heading: "Kết nối đã lưu, inference chưa được bật",
          detail: "Cần xác minh quyền API, refresh token, quota/billing và nguồn giá trước khi AffiHub gửi yêu cầu tạo nội dung."
        },
        scope_missing: {
          heading: "Tài khoản chưa cấp quyền dùng model",
          detail: "Tài khoản Google chưa cấp scope #{display_name} cần thiết. Đăng nhập lại và cấp quyền trước khi dùng model."
        },
        permissions: {
          granted: "OAuth #{display_name} đã cấp quyền đọc model.",
          missing: "OAuth chưa cấp quyền #{display_name} cần thiết.",
          detail: "Quota, billing và inference chưa được xác minh cho Google Cloud project."
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
end
