require "rails_helper"

RSpec.describe Publications::TikTokPublisher, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version, status: "ready") }
    let(:social_connection) { create(:social_connection, provider: "tiktok", external_user_id: "creator-1") }
    let(:social_destination) do
      create(:social_destination, social_connection:, provider: "tiktok", external_id: "creator-1")
    end
    let(:consent_snapshot) do
      {
        "privacy_level" => "SELF_ONLY",
        "allow_comment" => true,
        "allow_duet" => false,
        "allow_stitch" => true,
        "is_aigc" => true,
        "music_usage_confirmed" => true,
        "creator_account_private" => true
      }
    end
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
    let(:creator_info) do
      {
        "privacy_level_options" => [ "SELF_ONLY", "PUBLIC_TO_EVERYONE" ],
        "comment_disabled" => false,
        "duet_disabled" => true,
        "stitch_disabled" => false,
        "max_video_post_duration_sec" => 120
      }
    end
    let(:upload_url) { "https://upload.example.test/video?upload_token=signed-tiktok-upload-secret" }
    let(:publish_id) { "tiktok-publish-1" }
    let(:client) { double("TikTok::Client") }
    let(:publisher) { described_class.new(workflow_run_id: workflow_run.id) }
    let(:logger_output) { StringIO.new }
    let(:original_logger) { Rails.logger }

    before do
      tiktok_configuration = Rails.application.config_for(:tiktok).deep_symbolize_keys.deep_merge(
        max_distinct_creators_per_24_hours: 1
      )
      allow(Rails.application).to receive(:config_for).and_call_original
      allow(Rails.application).to receive(:config_for).with("tiktok").and_return(tiktok_configuration)
      allow(TikTok::Client).to receive(:new).and_return(client)
      allow(client).to receive(:creator_info).and_return("data" => creator_info, "error" => { "code" => "ok" })
      allow(client).to receive(:file_upload_source_info) do |file_size:|
        {
          "source" => "FILE_UPLOAD",
          "video_size" => file_size,
          "chunk_size" => file_size,
          "total_chunk_count" => 1
        }
      end
      allow(client).to receive(:init_video_publish).and_return(
        "data" => { "publish_id" => publish_id, "upload_url" => upload_url },
        "error" => { "code" => "ok" }
      )
      allow(client).to receive(:upload_file) do |file_size:, resume_offset:, **_upload_arguments, &checkpoint|
        checkpoint.call([ resume_offset + 5, file_size ].min)
        checkpoint.call(file_size)
        { "uploaded_bytes" => file_size }
      end
      allow(client).to receive(:publish_status).and_return(
        "data" => { "status" => "PUBLISH_COMPLETE", "publicaly_available_post_id" => [] },
        "error" => { "code" => "ok" }
      )
      allow(client).to receive(:video_query).and_return(nil)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      render_version.file.attach(
        io: StringIO.new("video bytes"),
        filename: "render.mp4",
        content_type: "video/mp4"
      )
      Rails.logger = ActiveSupport::Logger.new(logger_output)
    end

    after do
      Rails.logger = original_logger
    end

    it "returns false without an explicit privacy choice" do
      publication.update!(consent_snapshot: {})

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:init_video_publish)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when PUBLIC_TO_EVERYONE is blocked before TikTok audit" do
      publication.update!(consent_snapshot: consent_snapshot.merge("privacy_level" => "PUBLIC_TO_EVERYONE"))

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_privacy_not_allowed")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false unless the user confirms the creator account is private before TikTok audit" do
      publication.update!(consent_snapshot: consent_snapshot.merge("creator_account_private" => false))

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_private_account_not_confirmed")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when the user has not confirmed music usage" do
      publication.update!(consent_snapshot: consent_snapshot.merge("music_usage_confirmed" => false))

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_music_usage_not_confirmed")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when AI disclosure consent is missing" do
      publication.update!(consent_snapshot: consent_snapshot.except("is_aigc"))

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_ai_disclosure_not_confirmed")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when the TikTok caption exceeds its UTF-16 length limit" do
      publication.update!(caption: "😀" * 1_101)

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_caption_too_long")
      expect(client).not_to have_received(:creator_info)
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when consent enables an interaction disabled by creator_info" do
      publication.update!(consent_snapshot: consent_snapshot.merge("allow_duet" => true))

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:init_video_publish)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when comments are disabled by creator_info" do
      allow(client).to receive(:creator_info).and_return(
        "data" => creator_info.merge("comment_disabled" => true),
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_creator_interaction_disabled")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when stitch is disabled by creator_info" do
      publication.update!(consent_snapshot: consent_snapshot.merge("allow_stitch" => true))
      allow(client).to receive(:creator_info).and_return(
        "data" => creator_info.merge("stitch_disabled" => true),
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_creator_interaction_disabled")
      expect(client).not_to have_received(:init_video_publish)
    end

    context "when a scheduled Publication's saved creator consent is no longer valid" do
      it "returns the Publication to manual review and pauses its Schedule" do
        schedule = create(:schedule, render_version:, recurrence: "daily")
        schedule_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched")
        schedule_consent_snapshot = consent_snapshot.merge(
          "tiktok_social_connection_id" => social_connection.id,
          "tiktok_creator_id" => social_destination.external_id,
          "tiktok_schedule_id" => schedule.id
        )
        schedule_destination = create(
          :schedule_destination,
          schedule:,
          social_destination:,
          consent_snapshot: schedule_consent_snapshot
        )
        publication.update!(
          schedule_occurrence:,
          consent_snapshot: schedule_consent_snapshot.merge(
            "tiktok_render_version_id" => render_version.id,
            "tiktok_publication_id" => publication.id
          )
        )
        allow(client).to receive(:creator_info).and_return(
          "data" => creator_info.merge("comment_disabled" => true),
          "error" => { "code" => "ok" }
        )

        expect(publisher.call).to eq(false)

        expect(publication.reload.status).to eq("draft")
        expect(publication.safe_error_code).to eq("tiktok_creator_interaction_disabled")
        expect(workflow_run.reload.status).to eq("failed")
        expect(schedule.reload.status).to eq("paused")
        expect(schedule_destination.reload.consent_snapshot).to eq(schedule_consent_snapshot)
        expect(client).not_to have_received(:init_video_publish)
      end
    end

    it "returns false for a new creator when the app-local creator cap is full" do
      prior_social_connection = create(:social_connection, provider: "tiktok")
      prior_social_destination = create(
        :social_destination,
        social_connection: prior_social_connection,
        provider: "tiktok"
      )
      prior_publication = create(
        :publication,
        social_destination: prior_social_destination,
        status: "published"
      )
      prior_workflow_run = create(
        :workflow_run,
        workflowable: prior_publication,
        operation: "publication_publish",
        stage: "publish",
        status: "completed"
      )
      create(
        :outbound_attempt,
        workflow_run: prior_workflow_run,
        stage: "publish",
        status: "confirmed",
        request_started_at: 1.hour.ago,
        sender_stopped_at: 1.hour.ago
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("tiktok_app_creator_cap_reached")
      expect(client).not_to have_received(:creator_info)
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns true when the current creator already holds the app-local slot" do
      prior_social_destination = create(
        :social_destination,
        social_connection: social_connection,
        provider: "tiktok"
      )
      prior_publication = create(
        :publication,
        social_destination: prior_social_destination,
        status: "published"
      )
      prior_workflow_run = create(
        :workflow_run,
        workflowable: prior_publication,
        operation: "publication_publish",
        stage: "publish",
        status: "completed"
      )
      create(
        :outbound_attempt,
        workflow_run: prior_workflow_run,
        stage: "publish",
        status: "confirmed",
        request_started_at: 1.hour.ago,
        sender_stopped_at: 1.hour.ago
      )

      expect(publisher.call).to eq(true)
    end

    it "returns true without repeating work for a Publication already marked published" do
      publication.update!(status: "published")

      expect(publisher.call).to eq(true)

      expect(client).not_to have_received(:creator_info)
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false for branded content with SELF_ONLY privacy" do
      publication.update!(
        consent_snapshot: consent_snapshot.merge("brand_content_toggle" => true)
      )

      expect(publisher.call).to eq(false)

      expect(client).not_to have_received(:init_video_publish)
      expect(publication.reload.status).to eq("approved")
    end

    it "returns false when creator_info reports the creator posting cap" do
      allow(client).to receive(:creator_info).and_return(
        "data" => {},
        "error" => { "code" => "spam_risk_too_many_posts" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("spam_risk_too_many_posts")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns false when TikTok reports the app active-user cap" do
      allow(client).to receive(:creator_info).and_return(
        "data" => {},
        "error" => { "code" => "reached_active_user_cap" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.safe_error_code).to eq("reached_active_user_cap")
      expect(client).not_to have_received(:init_video_publish)
    end

    it "returns true after querying creator settings before initializing a TikTok post" do
      expect(client).to receive(:creator_info).ordered.and_return(
        "data" => creator_info,
        "error" => { "code" => "ok" }
      )
      expect(client).to receive(:init_video_publish).ordered.and_return(
        "data" => { "publish_id" => publish_id, "upload_url" => upload_url },
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(true)
    end

    it "returns one successful publish when two workers start the same TikTok workflow", database_cleaner: :truncation do
      publication
      workflow_run
      ready = Queue.new
      start = Queue.new
      outcomes = Queue.new
      allow(client).to receive(:creator_info) do
        ready << true
        start.pop
        { "data" => creator_info, "error" => { "code" => "ok" } }
      end
      expect(client).to receive(:init_video_publish).once.and_return(
        "data" => { "publish_id" => publish_id, "upload_url" => upload_url },
        "error" => { "code" => "ok" }
      )
      publisher_threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            publisher_service = described_class.new(workflow_run_id: workflow_run.id)
            publisher_service.call
            outcomes << publisher_service.success?
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      publisher_threads.each(&:value)

      publish_outcomes = 2.times.map { outcomes.pop }

      expect(publish_outcomes.count(true)).to eq(1)
      expect(publish_outcomes.count(false)).to eq(1)
      expect(publication.reload.status).to eq("published")
    end

    it "returns true after initializing FILE_UPLOAD with the saved TikTok disclosures" do
      expect(client).to receive(:init_video_publish) do |**arguments|
        expect(arguments.fetch(:access_token)).to eq("page-access-token")
        expect(arguments.fetch(:post_info).slice(
          "title", "privacy_level", "disable_comment", "disable_duet", "disable_stitch", "is_aigc"
        )).to eq(
          "title" => publication.caption,
          "privacy_level" => "SELF_ONLY",
          "disable_comment" => false,
          "disable_duet" => true,
          "disable_stitch" => false,
          "is_aigc" => true
        )
        expect(arguments.fetch(:source_info).fetch("source")).to eq("FILE_UPLOAD")
      end.and_return(
        "data" => { "publish_id" => publish_id, "upload_url" => upload_url },
        "error" => { "code" => "ok" }
      )
      expect(publisher.call).to eq(true)
    end

    it "returns true after persisting each upload offset before continuing to the next chunk" do
      allow(client).to receive(:upload_file) do |file_size:, resume_offset:, **_upload_arguments, &checkpoint|
        checkpoint.call([ resume_offset + 5, file_size ].min)
        expect(workflow_run.reload.checkpoint.fetch("upload_offset")).to eq([ resume_offset + 5, file_size ].min)
        checkpoint.call(file_size)
        { "uploaded_bytes" => file_size }
      end

      expect(publisher.call).to eq(true)

      expect(workflow_run.reload.checkpoint.slice("publish_id", "upload_offset")).to eq(
        "publish_id" => publish_id,
        "upload_offset" => publication.render_version.file.byte_size
      )
    end

    it "returns true while keeping Commercial Content toggles off when consent omits them" do
      publication.update!(consent_snapshot: consent_snapshot.except("brand_organic_toggle", "brand_content_toggle"))
      expect(client).to receive(:init_video_publish) do |**arguments|
        expect(arguments.fetch(:post_info).slice("brand_organic_toggle", "brand_content_toggle")).to eq(
          "brand_organic_toggle" => false,
          "brand_content_toggle" => false
        )
      end.and_return(
        "data" => { "publish_id" => publish_id, "upload_url" => upload_url },
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(true)
    end

    context "when TikTok has not finished processing" do
      before do
        allow(client).to receive(:publish_status).and_return(
          "data" => { "status" => "PROCESSING_UPLOAD", "publicaly_available_post_id" => [] },
          "error" => { "code" => "ok" }
        )
      end

      it "returns true while the Publication remains processing until TikTok completes" do
        expect(publisher.call).to eq(true)

        expect(publication.reload.status).to eq("processing")
        expect(publication.published_at).to eq(nil)
      end

      it "enqueues a status poll for a nonfinal TikTok response" do
        expect { publisher.call }.to have_enqueued_job(Publications::PublishJob).with(workflow_run.id)
      end
    end

    it "returns true and records PUBLISH_COMPLETE without inventing an ID or permalink for SELF_ONLY" do
      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq(nil)
      expect(publication.permalink).to eq(nil)
      expect(publication.provider_reference).to eq("provider" => "tiktok", "publish_id" => publish_id)
      expect(publication.published_at).not_to eq(nil)
      expect(client).not_to have_received(:video_query)
    end

    it "returns true and stores TikTok's share_url for a public post returned by video_query" do
      social_connection.update!(scopes: %w[user.info.basic video.publish video.list])
      allow(client).to receive(:publish_status).and_return(
        "data" => { "status" => "PUBLISH_COMPLETE", "publicaly_available_post_id" => [ "post-1" ] },
        "error" => { "code" => "ok" }
      )
      allow(client).to receive(:video_query).and_return(
        "id" => "post-1",
        "share_url" => "https://www.tiktok.com/@creator/video/post-1"
      )

      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("post-1")
      expect(publication.permalink).to eq("https://www.tiktok.com/@creator/video/post-1")
    end

    it "returns true without saving a public post ID or permalink without the video.list scope" do
      allow(client).to receive(:publish_status).and_return(
        "data" => { "status" => "PUBLISH_COMPLETE", "publicaly_available_post_id" => [ "post-1" ] },
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(true)

      expect(publication.reload.platform_post_id).to eq(nil)
      expect(publication.permalink).to eq(nil)
      expect(client).not_to have_received(:video_query)
    end

    it "returns true without a public post ID or permalink when video_query omits share_url" do
      social_connection.update!(scopes: %w[user.info.basic video.publish video.list])
      allow(client).to receive(:publish_status).and_return(
        "data" => { "status" => "PUBLISH_COMPLETE", "publicaly_available_post_id" => [ "post-1" ] },
        "error" => { "code" => "ok" }
      )
      allow(client).to receive(:video_query).and_return("id" => "post-1")

      expect(publisher.call).to eq(true)

      expect(publication.reload.platform_post_id).to eq(nil)
      expect(publication.permalink).to eq(nil)
    end

    it "returns false and marks the Publication failed when TikTok reports FAILED" do
      allow(client).to receive(:publish_status).and_return(
        "data" => { "status" => "FAILED" },
        "error" => { "code" => "ok" }
      )

      expect(publisher.call).to eq(false)

      expect(publication.reload.status).to eq("failed")
      expect(workflow_run.reload.status).to eq("failed")
    end

    it "returns true when resuming status polling without starting another upload" do
      workflow_run.update!(
        checkpoint: {
          "publish_id" => publish_id,
          "upload_url" => upload_url,
          "upload_offset" => publication.render_version.file.byte_size,
          "upload_complete" => true,
          "status_poll_attempts" => 0
        }
      )
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "publish",
        status: "confirmed",
        request_started_at: 1.minute.ago,
        sender_stopped_at: 1.minute.ago
      )

      expect(publisher.call).to eq(true)

      expect(publication.reload.status).to eq("published")
      expect(client).not_to have_received(:creator_info)
      expect(client).not_to have_received(:init_video_publish)
      expect(client).not_to have_received(:upload_file)
    end

    it "returns false and marks an ambiguous upload as OutcomeUnknown" do
      allow(client).to receive(:upload_file).and_raise(Net::ReadTimeout)

      expect(publisher.call).to eq(false)

      expect(publication.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("reconciliation_required")
    end

    context "when an upload already has an unknown outcome" do
      before do
        allow(client).to receive(:upload_file).and_raise(Net::ReadTimeout)
        publisher.call
      end

      it "returns false without starting another TikTok publish request" do
        retry_publisher = "Publications::TikTokPublisher".constantize.new(workflow_run_id: workflow_run.id)

        expect(retry_publisher.call).to eq(false)

        expect(client).to have_received(:init_video_publish).once
      end
    end

    it "does not write a signed upload URI to logs" do
      publisher.call

      expect(logger_output.string).not_to match(Regexp.union("signed-tiktok-upload-secret", upload_url))
    end
  end
end
