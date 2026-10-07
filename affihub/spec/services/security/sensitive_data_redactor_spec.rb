require "rails_helper"

RSpec.describe "Security::SensitiveDataRedactor", type: :service do
  describe "#call" do
    it "returns structured errors without credentials or signed upload values" do
      secrets = %w[access-secret refresh-secret]
      payload = {
        authorization: "Bearer access-secret",
        refresh_token: "refresh-secret",
        upload_uri: "https://upload.example/video?signature=private-signature&session=private-session"
      }
      safe_payload = "Security::SensitiveDataRedactor".constantize.new(secret_values: secrets).call(payload).to_json

      expect(safe_payload).not_to include("access-secret", "refresh-secret", "private-signature", "private-session")
    end

    it "returns safe error text without credential values embedded in the message" do
      message = "Upload failed with Bearer access-secret and https://upload.example/session?signature=private-signature"
      safe_message = "Security::SensitiveDataRedactor".constantize.new(secret_values: [ "access-secret" ]).call(message)

      expect(safe_message).not_to include("access-secret", "private-signature")
    end
  end
end
