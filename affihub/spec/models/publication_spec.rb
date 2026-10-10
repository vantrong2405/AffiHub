require "rails_helper"

RSpec.describe Publication, type: :model do
  describe "Telegram alert enqueueing" do
    it "enqueues an alert when a manual Publication fails" do
      publication = create(:publication, status: "approved")

      expect do
        publication.update!(status: "failed", safe_error_code: "youtube_publish_failed")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("publication_failed", "Publication", publication.id, {})
        .exactly(1).times
    end

    it "enqueues an alert when a Publication outcome becomes unknown" do
      publication = create(:publication, status: "uploading")

      expect do
        publication.update!(status: "outcome_unknown", safe_error_code: "youtube_publish_outcome_unknown")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("publication_outcome_unknown", "Publication", publication.id, {})
        .exactly(1).times
    end

    it "enqueues a final success alert when an auto-published Publication completes" do
      schedule_occurrence = create(:schedule_occurrence)
      publication = create(:publication, schedule_occurrence:, status: "uploading")

      expect do
        publication.update!(status: "published", platform_post_id: "video-123", permalink: "https://example.test/video-123")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("auto_publish_succeeded", "Publication", publication.id, {})
        .exactly(1).times
    end

    it "enqueues a final failure alert when an auto-published Publication fails" do
      schedule_occurrence = create(:schedule_occurrence)
      publication = create(:publication, schedule_occurrence:, status: "uploading")

      expect do
        publication.update!(status: "failed", safe_error_code: "youtube_publish_failed")
      end.to have_enqueued_job(Telegram::Alerts::SendJob)
        .with("auto_publish_failed", "Publication", publication.id, {})
        .exactly(1).times
    end
  end

  describe "#status" do
    it "returns manual outcome not occurred when the operator confirms no post was created" do
      publication = build(:publication, status: "manual_outcome_not_occurred")

      expect(publication.status).to eq("manual_outcome_not_occurred")
    end
  end
end
