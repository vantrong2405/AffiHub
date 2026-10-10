require "rails_helper"

RSpec.describe Publications::InstagramPublisher, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version, status: "ready") }
    let(:social_connection) { create(:social_connection, provider: "instagram", external_user_id: "facebook-owner-1") }
    let(:social_destination) do
      create(
        :social_destination,
        social_connection:,
        provider: "instagram",
        external_id: "ig-business-1",
        access_token: "instagram-page-token",
        metadata: {
          "page_id" => "page-1",
          "instagram_business_account_id" => "ig-business-1",
          "instagram_account_type" => "BUSINESS"
        }
      )
    end
    let(:publication) do
      create(
        :publication,
        render_version:,
        social_destination:,
        status: "approved",
        caption: "Caption riêng cho Instagram"
      )
    end
    let(:workflow_run) do
      create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
    end
    let(:client) { double("Meta::Client") }
    let(:publisher) { described_class.new(workflow_run_id: workflow_run.id) }
    let(:upload_url) { "https://rupload.facebook.com/ig-api-upload/v26.0/creation-1?sig=signed-instagram-upload-secret" }
    let(:quota_response) do
      {
        "data" => [
          { "quota_usage" => 2, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } }
        ]
      }
    end

    before do
      allow(Meta::Client).to receive(:new).with(provider: :instagram).and_return(client)
      allow(client).to receive(:instagram_content_publishing_limit).and_return(quota_response)
      allow(client).to receive(:start_instagram_reel_upload).and_return("id" => "creation-1", "uri" => upload_url)
      allow(client).to receive(:upload_instagram_reel).and_return("success" => true)
      allow(client).to receive(:instagram_reel_status).and_return("status_code" => "FINISHED")
      allow(client).to receive(:publish_instagram_reel).and_return("id" => "instagram-media-1")
      allow(client).to receive(:instagram_media).and_return(
        "id" => "instagram-media-1",
        "permalink" => "https://www.instagram.com/reel/example/"
      )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      render_version.file.attach(
        io: StringIO.new("video bytes"),
        filename: "render.mp4",
        content_type: "video/mp4"
      )
    end

    it "returns false when the selected Instagram destination is not a Business account" do
      social_destination.update!(metadata: social_destination.metadata.merge("instagram_account_type" => "CREATOR"))

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("instagram_business_account_required")
      expect(client).not_to have_received(:start_instagram_reel_upload)
      expect(client).not_to have_received(:publish_instagram_reel)
    end

    it "returns false when the current Instagram publishing quota is exhausted" do
      allow(client).to receive(:instagram_content_publishing_limit).and_return(
        "data" => [ { "quota_usage" => 80, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } } ]
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("instagram_publishing_limit_reached")
      expect(client).not_to have_received(:start_instagram_reel_upload)
      expect(client).not_to have_received(:publish_instagram_reel)
    end

    it "returns false when the Instagram quota fills after upload but before media publish" do
      allow(client).to receive(:instagram_content_publishing_limit).and_return(
        quota_response,
        "data" => [ { "quota_usage" => 80, "config" => { "quota_total" => 80, "quota_duration" => 86_400 } } ]
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("instagram_publishing_limit_reached")
      expect(publication.status).to eq("failed")
      expect(client).to have_received(:instagram_content_publishing_limit).twice
      expect(client).not_to have_received(:publish_instagram_reel)
    end

    it "returns false when the current Instagram quota response has no usage or cap" do
      allow(client).to receive(:instagram_content_publishing_limit).and_return("data" => [ { "quota_usage" => nil, "config" => {} } ])

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("instagram_publishing_limit_unavailable")
      expect(client).not_to have_received(:start_instagram_reel_upload)
      expect(client).not_to have_received(:publish_instagram_reel)
    end

    it "returns true after uploading the local render and confirming the published Instagram media" do
      expect(client).to receive(:instagram_content_publishing_limit).ordered.with(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token"
      ).and_return(quota_response)
      expect(client).to receive(:start_instagram_reel_upload).ordered.with(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token",
        caption: "Caption riêng cho Instagram"
      ).and_return("id" => "creation-1", "uri" => upload_url)
      expect(client).to receive(:upload_instagram_reel).ordered.with(
        upload_url:,
        page_access_token: "instagram-page-token",
        file: anything,
        file_size: render_version.file.byte_size
      ).and_return("success" => true)
      expect(client).to receive(:instagram_reel_status).ordered.with(
        creation_id: "creation-1",
        page_access_token: "instagram-page-token"
      ).and_return("status_code" => "FINISHED")
      expect(client).to receive(:instagram_content_publishing_limit).ordered.with(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token"
      ).and_return(quota_response)
      expect(client).to receive(:publish_instagram_reel).ordered.with(
        instagram_user_id: "ig-business-1",
        page_access_token: "instagram-page-token",
        creation_id: "creation-1"
      ).and_return("id" => "instagram-media-1")
      expect(client).to receive(:instagram_media).ordered.with(
        media_id: "instagram-media-1",
        page_access_token: "instagram-page-token"
      ).and_return("id" => "instagram-media-1", "permalink" => "https://www.instagram.com/reel/example/")

      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("instagram-media-1")
      expect(publication.permalink).to eq("https://www.instagram.com/reel/example/")
      expect(workflow_run.reload.checkpoint.slice("creation_id", "upload_complete", "media_id")).to eq(
        "creation_id" => "creation-1",
        "upload_complete" => true,
        "media_id" => "instagram-media-1"
      )
    end

    it "returns true and queues a poll while the Instagram upload container is processing" do
      allow(client).to receive(:instagram_reel_status).and_return("status_code" => "IN_PROGRESS")

      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("processing")
      expect(client).not_to have_received(:publish_instagram_reel)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.length).to eq(1)
    end

    it "returns true after resuming a saved container without creating or uploading another one" do
      workflow_run.update!(checkpoint: {
        "creation_id" => "creation-1",
        "upload_url" => upload_url,
        "upload_complete" => true,
        "media_publish_started" => false
      })
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "publish",
        status: "confirmed",
        request_started_at: 1.minute.ago,
        sender_stopped_at: 1.minute.ago
      )

      expect(publisher.call).to eq(true)

      expect(client).not_to have_received(:start_instagram_reel_upload)
      expect(client).not_to have_received(:upload_instagram_reel)
      expect(publication.reload.status).to eq("published")
    end

    it "returns false and keeps an uncertain media publish in OutcomeUnknown" do
      allow(client).to receive(:publish_instagram_reel).and_raise(Meta::Client::Error, "network_request_failed")

      expect(publisher.call).to eq(false)

      expect(publication.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("reconciliation_required")
    end

    it "returns false on retry without sending a second media publish after an unknown result" do
      allow(client).to receive(:publish_instagram_reel).and_raise(Meta::Client::Error, "network_request_failed")
      publisher.call
      retry_publisher = described_class.new(workflow_run_id: workflow_run.id)

      expect(retry_publisher.call).to eq(false)

      expect(client).to have_received(:publish_instagram_reel).once
    end

    it "returns true and resolves the stored media permalink when reconciling a published container" do
      publication.update!(status: "outcome_unknown")
      workflow_run.update!(
        status: "reconciliation_required",
        checkpoint: {
          "creation_id" => "creation-1",
          "upload_complete" => true,
          "media_publish_started" => true,
          "media_id" => "instagram-media-1"
        }
      )
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "publish",
        status: "outcome_unknown",
        request_started_at: 1.minute.ago,
        sender_stopped_at: 1.minute.ago
      )
      allow(client).to receive(:instagram_reel_status).and_return("status_code" => "PUBLISHED")
      allow(client).to receive(:instagram_media).and_return(
        "id" => "instagram-media-1",
        "permalink" => "https://www.instagram.com/reel/reconciled/"
      )

      expect(publisher.call).to eq(true)

      expect(client).to have_received(:instagram_media).with(
        media_id: "instagram-media-1",
        page_access_token: "instagram-page-token"
      )
      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("instagram-media-1")
      expect(publication.permalink).to eq("https://www.instagram.com/reel/reconciled/")
    end

    it "does not write the signed Instagram upload URI to logs" do
      logger_output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(logger_output)

      publisher.call

      expect(logger_output.string).not_to match(Regexp.union("signed-instagram-upload-secret", upload_url))
    ensure
      Rails.logger = original_logger
    end
  end
end
