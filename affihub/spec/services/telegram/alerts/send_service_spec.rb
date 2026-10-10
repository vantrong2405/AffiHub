require "rails_helper"

RSpec.describe Telegram::Alerts::SendService, type: :service do
  describe "#call" do
    let(:telegram_client) { instance_double(Telegram::Client) }

    before do
      allow(Telegram::Client).to receive(:new).and_return(telegram_client)
      allow(telegram_client).to receive(:send_message).and_return(true)
    end

    it 'returns true after sending a worker-down alert' do
      service = described_class.new(event: :worker_down)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Solid Queue không còn worker hoạt động. Hãy kiểm tra tiến trình worker."
      ).once
    end

    it 'returns true after sending a failed Publication alert with its destination' do
      social_destination = create(:social_destination, name: "Page Ánh Dương")
      publication = create(
        :publication,
        social_destination:,
        status: "failed",
        safe_error_code: "youtube_publish_failed"
      )
      service = described_class.new(event: :publication_failed, record: publication)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Publication ##{publication.id} thất bại tại Page Ánh Dương. Mã lỗi: youtube_publish_failed."
      ).once
    end

    it 'returns true after sending an OutcomeUnknown alert with a manual check instruction' do
      social_destination = create(:social_destination, name: "Page Ánh Dương")
      publication = create(
        :publication,
        social_destination:,
        status: "outcome_unknown",
        safe_error_code: "youtube_publish_outcome_unknown"
      )
      service = described_class.new(event: :publication_outcome_unknown, record: publication)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Publication ##{publication.id} tại Page Ánh Dương chưa rõ kết quả. Hãy kiểm tra nền tảng trước khi thử lại."
      ).once
    end

    it 'returns true after sending a provider rate-limit alert with its safe error code' do
      service = described_class.new(
        event: :api_rate_limited,
        details: { integration: "YouTube Data API", safe_error_code: "youtube_quota_exhausted" }
      )

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] YouTube Data API đã chạm giới hạn. Mã lỗi: youtube_quota_exhausted."
      ).once
    end

    it 'returns true after sending a provider API error alert with its safe error code' do
      service = described_class.new(
        event: :api_error,
        details: { integration: "Meta Graph API", safe_error_code: "meta_graph_api_error" }
      )

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Meta Graph API gặp lỗi. Mã lỗi: meta_graph_api_error."
      ).once
    end

    it 'returns true after sending a failed auto-reply alert with its destination' do
      social_destination = create(:social_destination, name: "Page Ánh Dương")
      auto_reply_event = create(
        :auto_reply_event,
        social_destination:,
        status: "failed",
        safe_error_code: "auto_reply_reply_failed"
      )
      service = described_class.new(event: :auto_reply_failed, record: auto_reply_event)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Auto-reply tại Page Ánh Dương thất bại. Mã lỗi: auto_reply_reply_failed."
      ).once
    end

    it 'returns true after sending a Sheets alert when retries are exhausted' do
      sheet_sync = create(:sheet_sync, status: "failed", safe_error_code: "google_sheets_retries_exhausted")
      service = described_class.new(event: :sheet_sync_retries_exhausted, record: sheet_sync)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Đồng bộ Google Sheets đã hết số lần thử. Mã lỗi: google_sheets_retries_exhausted."
      ).once
    end

    it 'returns true after sending the final success of an auto-published Publication' do
      social_destination = create(:social_destination, name: "Page Ánh Dương")
      publication = create(:publication, social_destination:, status: "published")
      service = described_class.new(event: :auto_publish_succeeded, record: publication)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Publication tự đăng ##{publication.id} đã hoàn tất tại Page Ánh Dương."
      ).once
    end

    it 'returns true after sending the final failure of an auto-published Publication' do
      social_destination = create(:social_destination, name: "Page Ánh Dương")
      publication = create(
        :publication,
        social_destination:,
        status: "failed",
        safe_error_code: "youtube_publish_failed"
      )
      service = described_class.new(event: :auto_publish_failed, record: publication)

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "[AffiHub] Lượt tự đăng Publication ##{publication.id} thất bại tại Page Ánh Dương. Mã lỗi: youtube_publish_failed."
      ).once
    end

    it 'returns false when the Telegram API cannot send an alert' do
      allow(telegram_client).to receive(:send_message).and_return(false)
      service = described_class.new(event: :worker_down)

      expect(service.call).to eq(false)
    end
  end
end
