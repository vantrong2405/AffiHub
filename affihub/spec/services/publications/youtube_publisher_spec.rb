require "rails_helper"

RSpec.describe "Publications::YoutubePublisher", type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version, status: "ready") }
    let(:social_connection) do
      create(:social_connection, provider: "youtube", external_user_id: "google-sub-1")
    end
    let(:social_destination) do
      create(:social_destination, social_connection:, provider: "youtube", external_id: "channel-1")
    end
    let(:consent_snapshot) do
      {
        "upload_terms_confirmed" => true,
        "youtube_account_id" => "google-sub-1",
        "youtube_channel_id" => "channel-1",
        "render_version_id" => render_version.id,
        "confirmed_at" => Time.current.iso8601,
        "privacy_status" => "private",
        "self_declared_made_for_kids" => false,
        "contains_synthetic_media" => true
      }
    end
    let(:bound_consent_snapshot) { consent_snapshot.merge("publication_id" => publication.id) }
    let(:publication) do
      create(
        :publication,
        render_version:,
        social_destination:,
        status: "approved",
        consent_snapshot:
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
    let(:client) { instance_double(Youtube::Client) }
    let(:publisher) { Publications::YoutubePublisher.new(workflow_run_id: workflow_run.id) }
    let(:session_uri) { "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-session" }

    before do
      allow(Youtube::Client).to receive(:new).and_return(client)
      allow(client).to receive(:start_resumable_upload).and_return(session_uri)
      allow(client).to receive(:upload_status).and_return(uploaded_bytes: 0, video_id: nil)
      allow(client).to receive(:upload_remaining).and_return(
        uploaded_bytes: render_version.file.byte_size,
        video_id: "youtube-video-1"
      )
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "private", "uploadStatus" => "processed" },
        "processingDetails" => { "processingStatus" => "succeeded" }
      )
      render_version.file.attach(
        io: StringIO.new("rendered-video-bytes"),
        filename: "render.mp4",
        content_type: "video/mp4"
      )
      publication.update!(consent_snapshot: bound_consent_snapshot)
    end

    it "returns false before upload when the user has not confirmed YouTube upload terms" do
      publication.update!(consent_snapshot: bound_consent_snapshot.except("upload_terms_confirmed"))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when upload terms were confirmed for another account" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("youtube_account_id" => "another-google-sub"))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when upload terms were confirmed for another render version" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("render_version_id" => render_version.id + 1))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when upload terms were confirmed for another Publication" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("publication_id" => publication.id + 1))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when the user has not selected an allowed privacy status" do
      publication.update!(consent_snapshot: bound_consent_snapshot.except("privacy_status"))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
    end

    it "returns true after uploading with the user's unlisted privacy choice" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("privacy_status" => "unlisted"))
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "unlisted", "uploadStatus" => "processed" },
        "processingDetails" => { "processingStatus" => "succeeded" }
      )

      expect(publisher.call).to eq(true)

      expect(publication.reload.provider_reference).to eq(
        "provider" => "youtube",
        "video_id" => "youtube-video-1",
        "privacy_status" => "unlisted"
      )
    end

    it "returns true after uploading with the user's public privacy choice" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("privacy_status" => "public"))
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "public", "uploadStatus" => "processed" },
        "processingDetails" => { "processingStatus" => "succeeded" }
      )

      expect(publisher.call).to eq(true)

      expect(publication.reload.provider_reference).to eq(
        "provider" => "youtube",
        "video_id" => "youtube-video-1",
        "privacy_status" => "public"
      )
    end

    it "returns false when made-for-kids disclosure is missing" do
      publication.update!(consent_snapshot: bound_consent_snapshot.except("self_declared_made_for_kids"))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
    end

    it "returns false when synthetic-media disclosure is missing" do
      publication.update!(consent_snapshot: bound_consent_snapshot.except("contains_synthetic_media"))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:start_resumable_upload)
    end

    it "returns false and records OutcomeUnknown when a saved session cannot be reconciled" do
      workflow_run.update!(checkpoint: { "upload_session_uri" => "https://www.googleapis.com/upload/youtube/v3/videos?upload_id=signed-session" })
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "publish",
        status: "submitting",
        request_started_at: 1.minute.ago,
        request_timeout_at: 30.seconds.from_now
      )
      allow(client).to receive(:upload_status).and_raise(Youtube::Client::Error, "network_request_failed")

      expect(publisher.call).to eq(false)

      expect(client).to have_received(:upload_status)
      expect(client).not_to have_received(:start_resumable_upload)
      expect(publication.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("reconciliation_required")
    end

    it "returns true when a saved session is reconciled and the remaining upload completes" do
      workflow_run.update!(checkpoint: { "upload_session_uri" => session_uri, "uploaded_bytes" => 0 })
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "publish",
        status: "submitting",
        request_started_at: 1.minute.ago,
        request_timeout_at: 30.seconds.from_now
      )

      expect(publisher.call).to eq(true)

      expect(client).to have_received(:upload_status).with(
        access_token: social_destination.access_token,
        session_uri:,
        file_size: render_version.file.byte_size
      )
      expect(client).not_to have_received(:start_resumable_upload)
    end

    it "returns true and stores YouTube's ID and approved privacy after the upload is processed" do
      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("youtube-video-1")
      expect(publication.permalink).to eq("https://www.youtube.com/watch?v=youtube-video-1")
      expect(publication.provider_reference).to eq(
        "provider" => "youtube",
        "video_id" => "youtube-video-1",
        "privacy_status" => "private"
      )
    end

    it "returns true after sending the selected privacy and disclosure snapshot in videos.insert metadata" do
      publication.update!(consent_snapshot: bound_consent_snapshot.merge("privacy_status" => "unlisted"))
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "unlisted", "uploadStatus" => "processed" },
        "processingDetails" => { "processingStatus" => "succeeded" }
      )

      expect(publisher.call).to eq(true)

      expect(client).to have_received(:start_resumable_upload).with(
        access_token: social_destination.access_token,
        metadata: {
          "snippet" => {
            "title" => publication.caption,
            "description" => publication.caption,
            "tags" => []
          },
          "status" => {
            "privacyStatus" => "unlisted",
            "selfDeclaredMadeForKids" => false,
            "containsSyntheticMedia" => true
          }
        },
        file_size: render_version.file.byte_size,
        content_type: "video/mp4"
      )
    end

    it "returns true after checkpointing and sending an unacknowledged upload suffix" do
      allow(client).to receive(:upload_remaining).and_return(
        { uploaded_bytes: 5, video_id: nil },
        { uploaded_bytes: render_version.file.byte_size, video_id: "youtube-video-1" }
      )

      expect(publisher.call).to eq(true)

      expect(client).to have_received(:upload_remaining).twice
      expect(workflow_run.reload.checkpoint).to eq(
        "upload_session_uri" => session_uri,
        "uploaded_bytes" => render_version.file.byte_size,
        "upload_complete" => true,
        "video_id" => "youtube-video-1"
      )
    end

    it "returns true without repeating a Publication already marked published" do
      publication.update!(status: "published")

      expect(publisher.call).to eq(true)

      expect(client).not_to have_received(:start_resumable_upload)
      expect(client).not_to have_received(:upload_remaining)
    end

    it "returns false when the processed video has a different privacy status than the approved choice" do
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "public", "uploadStatus" => "processed" },
        "processingDetails" => { "processingStatus" => "succeeded" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.status).to eq("failed")
      expect(publication.safe_error_code).to eq("youtube_processing_failed")
    end

    it "returns true and queues a status check while YouTube is processing the uploaded video" do
      allow(client).to receive(:video_status).and_return(
        "id" => "youtube-video-1",
        "snippet" => { "channelId" => "channel-1" },
        "status" => { "privacyStatus" => "private", "uploadStatus" => "uploaded" },
        "processingDetails" => { "processingStatus" => "processing" }
      )

      expect { publisher.call }.to have_enqueued_job(Publications::PublishJob).with(workflow_run.id)

      expect(publication.reload.status).to eq("processing")
      expect(workflow_run.reload.status).to eq("queued")
    end
  end
end
