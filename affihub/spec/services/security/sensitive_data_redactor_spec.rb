require "rails_helper"

RSpec.describe Security::SensitiveDataRedactor, type: :service do
  describe "#call" do
    it "returns structured errors without credentials or signed upload values" do
      secrets = %w[access-secret refresh-secret]
      payload = {
        authorization: "Bearer access-secret",
        refresh_token: "refresh-secret",
        upload_uri: "https://upload.example/video?signature=private-signature&session=private-session"
      }
      safe_payload = described_class.new(secret_values: secrets).call(payload).to_json

      expect(safe_payload).not_to match(Regexp.union("access-secret", "refresh-secret", "private-signature", "private-session"))
    end

    it "returns safe error text without credential values embedded in the message" do
      message = "Upload failed with Bearer access-secret and https://upload.example/session?signature=private-signature"
      safe_message = described_class.new(secret_values: [ "access-secret" ]).call(message)

      expect(safe_message).not_to match(Regexp.union("access-secret", "private-signature"))
    end

    it "redacts the token from a TikTok signed upload URI" do
      upload_uri = "https://upload.example.test/video?upload_token=tiktok-upload-secret&expires=3600"
      safe_uri = described_class.new.call(upload_uri)

      expect(safe_uri).not_to match(Regexp.escape("tiktok-upload-secret"))
    end

    it "returns a YouTube resumable session URI with its upload ID filtered" do
      upload_uri = "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-secret&part=snippet,status"

      safe_uri = described_class.new.call(upload_uri)

      expect(safe_uri).to eq(
        "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=[FILTERED]&part=snippet,status"
      )
    end

    it "returns a Google Drive resumable session URI without its session secret" do
      upload_uri = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=drive-session-secret"

      safe_uri = described_class.new.call(upload_uri)

      expect(safe_uri).to eq(
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=[FILTERED]"
      )
    end
  end

  describe "Rails request logging" do
    it "returns a filtered YouTube upload ID from request parameters" do
      parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      filtered = parameter_filter.filter("upload_id" => "signed-secret")

      expect(filtered).to eq("upload_id" => "[FILTERED]")
    end
  end
end
