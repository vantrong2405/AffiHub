require "rails_helper"

RSpec.describe AiProviderConnectionsHelper, type: :helper do
  let(:gemini_scope) { "https://www.googleapis.com/auth/generative-language.retriever" }
  let(:gemini_provider_presentation) do
    {
      display_name: "Gemini API",
      required_scopes: [ gemini_scope ],
      model_selection_enabled: true,
      project_id: "affihub-test-project",
      quota_console_url: "https://console.cloud.google.com/apis/api/generativelanguage.googleapis.com/quotas",
      pricing_source_url: "https://ai.google.dev/gemini-api/docs/pricing"
    }
  end

  describe "#ai_provider_options_presentation" do
    it "returns a connect action when the provider callback origin matches" do
      provider_option = {
        provider: "gemini",
        label: "Gemini API",
        enabled: true,
        origin_matches: true,
        required_origin: "http://localhost:3000"
      }

      expect(helper.ai_provider_options_presentation(provider_options: [ provider_option ])).to eq(
        [
          {
            label: "Gemini API",
            availability_label: "Có thể kết nối",
            note: "Chờ xác minh quyền và hạn mức API.",
            action: {
              kind: :button,
              label: "Kết nối Gemini API",
              path: "/ai_provider_connections",
              params: { provider: "gemini" }
            }
          }
        ]
      )
    end

    it "returns a callback-origin link when the current origin does not match" do
      provider_option = {
        provider: "codex",
        label: "Codex",
        enabled: true,
        origin_matches: false,
        required_origin: "http://localhost:1455"
      }

      expect(helper.ai_provider_options_presentation(provider_options: [ provider_option ])).to eq(
        [
          {
            label: "Codex",
            availability_label: "Có thể kết nối",
            note: "Xác thực riêng; quyền tạo nội dung chưa được xác minh.",
            action: {
              kind: :link,
              label: "Mở AffiHub",
              href: "http://localhost:1455/ai_provider_connections",
              callback_origin: "http://localhost:1455"
            }
          }
        ]
      )
    end

    it "returns a disabled action when the provider is unavailable" do
      provider_option = {
        provider: "gemini",
        label: "Gemini API",
        enabled: false,
        origin_matches: false,
        required_origin: "http://localhost:3000"
      }

      expect(helper.ai_provider_options_presentation(provider_options: [ provider_option ])).to eq(
        [
          {
            label: "Gemini API",
            availability_label: "Chưa khả dụng",
            note: "Chờ xác minh quyền và hạn mức API.",
            action: { kind: :disabled, label: "Chưa khả dụng" }
          }
        ]
      )
    end
  end

  describe "#ai_provider_accounts_presentation" do
    it "returns the prepared account summary for a connection missing its required scope" do
      connection = build(
        :ai_provider_connection,
        id: 42,
        provider: "gemini",
        status: :scope_missing,
        display_name: nil,
        account_email: "creator@example.com"
      )

      expect(
        helper.ai_provider_accounts_presentation(
          connections: [ connection ],
          provider_presentations: { gemini: gemini_provider_presentation }
        )
      ).to eq(
        accounts: [
          {
            account_name: "creator@example.com",
            account_label: "Gemini API · creator@example.com",
            status: "scope_missing",
            summary: "Tài khoản chưa cấp scope Gemini API cần thiết.",
            action_label: "Quản lý model",
            path: "/ai_provider_connections/42"
          }
        ],
        has_accounts: true,
        empty_state: {
          heading: "Chưa có tài khoản AI nào",
          detail: "Chọn một nhà cung cấp khả dụng ở phía trên để kết nối tài khoản."
        }
      )
    end
  end

  describe "#ai_provider_connection_presentation" do
    it "returns prepared permission, model, and pending-status presentation" do
      connection = build(
        :ai_provider_connection,
        provider: "gemini",
        status: :pending_verification,
        scopes: [ gemini_scope ],
        last_verified_at: nil
      )

      expect(
        helper.ai_provider_connection_presentation(
          connection:,
          provider_presentation: gemini_provider_presentation,
          callback_origin: "http://localhost:3000",
          callback_origin_matches: true
        )
      ).to eq(
        {
          account_name: "AffiHub Creator",
          provider_name: "Gemini API",
          status: "pending_verification",
          status_notice: {
            class_name: "alert alert-warning",
            role: "status",
            heading: "Kết nối đã lưu, inference chưa được bật",
            detail: "AffiHub giữ inference ở trạng thái chờ xác minh đến khi giới hạn sử dụng và chi phí theo model được kiểm tra cho project này."
          },
          permissions: {
            message: "OAuth Gemini API đã cấp quyền đọc model.",
            detail: "Xem quota theo project và bảng giá Gemini API chính thức trước khi bật inference."
          },
          last_verified_label: "Chưa có",
          quota_and_pricing_sources: {
            project_id: "affihub-test-project",
            quota_url: "https://console.cloud.google.com/apis/api/generativelanguage.googleapis.com/quotas?project=affihub-test-project",
            pricing_url: "https://ai.google.dev/gemini-api/docs/pricing"
          },
          model_catalog: {
            enabled: true,
            has_options: true,
            heading: "Model của tài khoản",
            detail: "Chỉ model do chính tài khoản provider trả về mới được lưu lựa chọn.",
            empty: "Provider chưa trả model nào có thể chọn cho tài khoản này.",
            options: [ [ "Gemini 3.5 Flash-Lite", "models/gemini-3.5-flash-lite" ] ],
            selected_model: "models/gemini-3.5-flash-lite"
          },
          management_action: nil
        }
      )
    end

    it "returns a same-origin reauthentication action for a connection requiring login" do
      connection = build(
        :ai_provider_connection,
        id: 42,
        provider: "gemini",
        status: :reauth_required
      )

      presentation = helper.ai_provider_connection_presentation(
        connection:,
        provider_presentation: gemini_provider_presentation,
        callback_origin: "http://localhost:3000",
        callback_origin_matches: true
      )

      expect(presentation.fetch(:management_action)).to eq(
        {
          kind: :button,
          label: "Đăng nhập lại",
          path: "/ai_provider_connections",
          params: { provider: "gemini", ai_provider_connection_id: 42 }
        }
      )
    end
  end
end
