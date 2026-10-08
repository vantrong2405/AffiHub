require "rails_helper"

RSpec.describe AiProviderConnections::IndexService, type: :service do
  describe "#call" do
    it "lists connected accounts and the four product choices without exposing credentials" do
      connection = create(:ai_provider_connection, access_token: "openai-secret-token")
      service = described_class.new(current_origin: "http://localhost:3000")

      expect(service.call).to be(true)
      expect(service.ai_provider_connections).to eq([ connection ])
      expect(service.provider_options).to eq(
        [
          {
            key: "chatgpt", provider: "openai", label: "ChatGPT", enabled: true,
            note: "Tiếp tục bằng tài khoản ChatGPT.", origin_matches: false, required_origin: "http://127.0.0.1:3000"
          },
          {
            key: "codex", provider: "codex", label: "Codex", enabled: true,
            note: "Xác thực riêng; quyền tạo nội dung chưa được xác minh.", origin_matches: false, required_origin: "http://localhost:1455"
          },
          {
            key: "gemini", label: "Gemini API", enabled: true,
            note: "Chờ xác minh quyền và hạn mức API.", origin_matches: true, required_origin: "http://localhost:3000"
          },
          {
            key: "antigravity", label: "Antigravity", enabled: false,
            note: "Chưa có quyền tích hợp cho AffiHub.", origin_matches: false, required_origin: nil
          }
        ]
      )
      expect(service.provider_options.to_json).not_to include("openai-secret-token")
    end
  end
end
