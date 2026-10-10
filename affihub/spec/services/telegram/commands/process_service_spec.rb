require "rails_helper"

RSpec.describe Telegram::Commands::ProcessService, type: :service do
  describe "#call" do
    let(:telegram_client) { instance_double(Telegram::Client) }

    before do
      allow(Telegram::Client).to receive(:new).and_return(telegram_client)
      allow(telegram_client).to receive(:send_message).and_return(true)
    end

    it 'returns true after sending current worker and Publication status' do
      scheduled_publication = create(:publication, status: "scheduled")
      unknown_publication = create(
        :publication,
        status: "outcome_unknown",
        safe_error_code: "youtube_publish_outcome_unknown"
      )
      service = described_class.new(chat_id: "1001", command: "/status")

      expect(service.call).to eq(true)
      expect(telegram_client).to have_received(:send_message).with(
        chat_id: "1001",
        text: "Worker: Chưa thể kiểm tra\nPublication đang lên lịch: 1\nPublication chưa rõ kết quả: 1\nLỗi gần nhất: youtube_publish_outcome_unknown"
      ).once
      expect(scheduled_publication.reload.status).to eq("scheduled")
      expect(unknown_publication.reload.status).to eq("outcome_unknown")
    end

    it "pauses auto-publish for the next Scheduler claim" do
      automation_control = AutomationControl.current
      service = described_class.new(chat_id: "1001", command: "/pause_auto_publish")

      expect { service.call }
        .to change { automation_control.reload.auto_publish_paused }
        .from(false).to(true)
    end

    it "resumes auto-publish for the next Scheduler claim" do
      automation_control = AutomationControl.current
      automation_control.update!(auto_publish_paused: true)
      service = described_class.new(chat_id: "1001", command: "/resume_auto_publish")

      expect { service.call }
        .to change { automation_control.reload.auto_publish_paused }
        .from(true).to(false)
    end

    it "pauses auto-reply for the next comment claim" do
      automation_control = AutomationControl.current
      service = described_class.new(chat_id: "1001", command: "/pause_auto_reply")

      expect { service.call }
        .to change { automation_control.reload.auto_responder_paused }
        .from(false).to(true)
    end

    it "resumes auto-reply for the next comment claim" do
      automation_control = AutomationControl.current
      automation_control.update!(auto_responder_paused: true)
      service = described_class.new(chat_id: "1001", command: "/resume_auto_reply")

      expect { service.call }
        .to change { automation_control.reload.auto_responder_paused }
        .from(true).to(false)
    end

    it 'returns false without replying or changing automation for an unallowlisted chat' do
      automation_control = AutomationControl.current
      service = described_class.new(chat_id: "9999", command: "/pause_auto_publish")

      expect(service.call).to eq(false)
      expect(automation_control.reload.auto_publish_paused).to eq(false)
      expect(telegram_client).not_to have_received(:send_message)
      expect(automation_control.reload.auto_responder_paused).to eq(false)
    end

    it 'returns false for a command outside the supported set' do
      service = described_class.new(chat_id: "1001", command: "/restart_server")

      expect(service.call).to eq(false)
      expect(telegram_client).not_to have_received(:send_message)
    end

    it 'returns false when Telegram cannot acknowledge an allowed command' do
      allow(telegram_client).to receive(:send_message).and_return(false)
      service = described_class.new(chat_id: "1001", command: "/pause_auto_reply")

      expect(service.call).to eq(false)
    end
  end
end
