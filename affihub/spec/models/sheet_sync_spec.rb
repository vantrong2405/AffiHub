require "rails_helper"

RSpec.describe SheetSync, type: :model do
  describe "Telegram alert enqueueing" do
    it "enqueues an alert when Sheets retries are exhausted" do
      sheet_sync = create(:sheet_sync, status: "syncing")

      expect do
        sheet_sync.update!(status: "failed", safe_error_code: "google_sheets_retries_exhausted")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("sheet_sync_retries_exhausted", "SheetSync", sheet_sync.id, {})
        .exactly(1).times
    end

    it "enqueues an alert when Sheets retries end with an unknown outcome" do
      sheet_sync = create(:sheet_sync, status: "syncing")

      expect do
        sheet_sync.update!(status: "outcome_unknown", safe_error_code: "google_sheets_sync_outcome_unknown")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("sheet_sync_retries_exhausted", "SheetSync", sheet_sync.id, {})
        .exactly(1).times
    end
  end
end
