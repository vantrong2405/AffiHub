require "rails_helper"

RSpec.describe AutoReplyEvent, type: :model do
  describe "Telegram alert enqueueing" do
    it "enqueues an alert when an auto-reply fails" do
      auto_reply_event = create(:auto_reply_event, status: "queued")

      expect do
        auto_reply_event.update!(status: "failed", safe_error_code: "auto_reply_reply_failed")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("auto_reply_failed", "AutoReplyEvent", auto_reply_event.id, {})
        .exactly(1).times
    end

    it "enqueues an alert when an auto-reply outcome becomes unknown" do
      auto_reply_event = create(:auto_reply_event, status: "queued")

      expect do
        auto_reply_event.update!(status: "outcome_unknown", safe_error_code: "auto_reply_outcome_unknown")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("auto_reply_outcome_unknown", "AutoReplyEvent", auto_reply_event.id, {})
        .exactly(1).times
    end
  end
end
