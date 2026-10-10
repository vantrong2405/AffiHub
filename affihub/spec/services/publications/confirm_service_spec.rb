require "rails_helper"

RSpec.describe Publications::ConfirmService, type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:render_version) { create(:render_version) }
    let(:social_destination) { create(:social_destination) }
    let(:publication) do
      create(:publication, render_version:, social_destination:, status: "draft")
    end
    let(:destination_results) do
      { social_destination.id.to_s => { "status" => "ready" } }
    end
    let(:preflight_report) do
      create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results:
      )
    end
    let(:service) do
      described_class.new(
        video_project_id: publication.render_version.video_project_id,
        publication_id: publication.id,
        preflight_report_id: preflight_report.id
      )
    end

    it "approves only the reviewed Publication and queues its workflow" do
      expect { service.call }.to have_enqueued_job(Publications::PublishJob)

      expect(service).to be_success
      expect(publication.reload.status).to eq("approved")
      expect(WorkflowRun.find_by!(workflowable: publication)).to have_attributes(status: "queued")
    end

    it 'returns true and queues publication when the Drive side job cannot be enqueued' do
      google_connection = create(:google_connection, integration: "drive")
      render_version.update!(status: "ready")
      render_version.file.attach(io: StringIO.new("render bytes"), filename: "render.mp4", content_type: "video/mp4")
      allow(DriveExports::UploadJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError)

      expect(service.call).to eq(true)

      expect(publication.reload.status).to eq("approved")
      expect(DriveExport.find_by!(render_version: render_version, google_connection:).attributes.slice("status", "safe_error_code")).to eq(
        "status" => "failed",
        "safe_error_code" => "google_drive_job_enqueue_failed"
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) }).to eq([ Publications::PublishJob ])
    end

    context "when a scheduled Publication needs manual confirmation again" do
      it "returns the existing workflow to the queue without creating another workflow" do
        schedule = create(:schedule, render_version:, recurrence: "daily", status: "paused")
        schedule_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched")
        publication.update!(schedule_occurrence:)
        workflow_run = create(
          :workflow_run,
          workflowable: publication,
          operation_id: "publication-#{publication.id}-publish",
          operation: "publication_publish",
          stage: "publish",
          status: "failed"
        )

        expect { service.call }.to have_enqueued_job(Publications::PublishJob).exactly(1).times

        expect(service.success?).to eq(true)
        expect(publication.reload.status).to eq("approved")
        expect(workflow_run.reload.status).to eq("queued")
        expect(workflow_run.checkpoint.fetch("scheduled_manual_confirmation_at")).to be_present
        expect(publication.workflow_runs.count).to eq(1)
      end
    end

    context "when a YouTube Publication has no upload terms confirmation" do
      let(:social_destination) do
        social_connection = create(
          :social_connection,
          provider: "youtube",
          external_user_id: "google-sub-1"
        )
        create(
          :social_destination,
          social_connection:,
          provider: "youtube",
          external_id: "channel-1"
        )
      end

      it "returns failure without approving or enqueueing the Publication" do
        expect { service.call }.not_to have_enqueued_job(Publications::PublishJob)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
        expect(WorkflowRun.where(workflowable: publication)).to be_empty
      end
    end

    context "when a YouTube Publication has complete consent bound to its current target" do
      let(:social_destination) do
        social_connection = create(
          :social_connection,
          provider: "youtube",
          external_user_id: "google-sub-1"
        )
        create(
          :social_destination,
          social_connection:,
          provider: "youtube",
          external_id: "channel-1"
        )
      end
      let(:publication) do
        youtube_publication = create(
          :publication,
          render_version:,
          social_destination:,
          status: "draft"
        )
        youtube_publication.update!(
          consent_snapshot: {
            "upload_terms_confirmed" => true,
            "youtube_account_id" => "google-sub-1",
            "youtube_channel_id" => "channel-1",
            "render_version_id" => render_version.id,
            "publication_id" => youtube_publication.id,
            "confirmed_at" => Time.current.iso8601,
            "privacy_status" => "private",
            "self_declared_made_for_kids" => false,
            "contains_synthetic_media" => false
          }
        )
        youtube_publication
      end

      it "approves and queues the consented YouTube Publication" do
        expect { service.call }.to have_enqueued_job(Publications::PublishJob)

        expect(service).to be_success
        expect(publication.reload.status).to eq("approved")
      end

      it "returns success when the user confirms an unlisted YouTube upload" do
        publication.update!(consent_snapshot: publication.consent_snapshot.merge("privacy_status" => "unlisted"))

        expect { service.call }.to have_enqueued_job(Publications::PublishJob)

        expect(service.success?).to eq(true)
        expect(publication.reload.status).to eq("approved")
      end

      it "returns success when the user confirms a public YouTube upload" do
        publication.update!(consent_snapshot: publication.consent_snapshot.merge("privacy_status" => "public"))

        expect { service.call }.to have_enqueued_job(Publications::PublishJob)

        expect(service.success?).to eq(true)
        expect(publication.reload.status).to eq("approved")
      end
    end

    context "when a TikTok Publication has no explicit privacy consent" do
      let(:social_destination) do
        social_connection = create(
          :social_connection,
          provider: "tiktok",
          external_user_id: "creator-1"
        )
        create(
          :social_destination,
          social_connection:,
          provider: "tiktok",
          external_id: "creator-1"
        )
      end

      it "returns failure without approving or enqueueing the Publication" do
        expect { service.call }.not_to have_enqueued_job(Publications::PublishJob)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
        expect(WorkflowRun.where(workflowable: publication)).to be_empty
      end
    end

    context "when a TikTok Publication has complete consent bound to its current creator" do
      let(:social_destination) do
        social_connection = create(
          :social_connection,
          provider: "tiktok",
          external_user_id: "creator-1"
        )
        create(
          :social_destination,
          social_connection:,
          provider: "tiktok",
          external_id: "creator-1"
        )
      end
      let(:publication) do
        tiktok_publication = create(
          :publication,
          render_version:,
          social_destination:,
          status: "draft"
        )
        tiktok_publication.update!(
          consent_snapshot: {
            "privacy_level" => "SELF_ONLY",
            "allow_comment" => false,
            "allow_duet" => false,
            "allow_stitch" => false,
            "brand_organic_toggle" => false,
            "brand_content_toggle" => false,
            "is_aigc" => true,
            "creator_account_private" => true,
            "music_usage_confirmed" => true,
            "tiktok_social_connection_id" => social_destination.social_connection_id,
            "tiktok_creator_id" => "creator-1",
            "tiktok_render_version_id" => render_version.id,
            "tiktok_publication_id" => tiktok_publication.id,
            "tiktok_confirmed_at" => Time.current.iso8601
          }
        )
        tiktok_publication
      end

      it "approves and queues the consented TikTok Publication" do
        expect { service.call }.to have_enqueued_job(Publications::PublishJob)

        expect(service).to be_success
        expect(publication.reload.status).to eq("approved")
      end

      it "keeps the TikTok Publication as a draft when consent belongs to another creator" do
        publication.update!(consent_snapshot: publication.consent_snapshot.merge("tiktok_creator_id" => "other-creator"))

        expect(service.call).to eq(false)

        expect(publication.reload.status).to eq("draft")
        expect(WorkflowRun.where(workflowable: publication)).to be_empty
      end

      it "keeps a private TikTok Publication as a draft when branded content is selected" do
        publication.update!(consent_snapshot: publication.consent_snapshot.merge("brand_content_toggle" => true))

        expect(service.call).to eq(false)

        expect(publication.reload.status).to eq("draft")
        expect(WorkflowRun.where(workflowable: publication)).to be_empty
      end
    end

    context "when the destination is now blocked by preflight" do
      let(:destination_results) do
        { social_destination.id.to_s => { "status" => "blocked" } }
      end

      it "keeps the draft and does not queue a publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the report does not include the Publication destination" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version:,
          checked_destination_ids: [],
          destination_results: {}
        )
      end

      it "returns failure without starting the publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
      end
    end

    context "when the report belongs to another render version" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version: create(:render_version),
          checked_destination_ids: [ social_destination.id ],
          destination_results:
        )
      end

      it "returns failure without starting the publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
      end
    end

    context "when a newer report blocks the destination" do
      let!(:latest_preflight_report) do
        create(
          :preflight_report,
          render_version:,
          checked_destination_ids: [ social_destination.id ],
          destination_results: { social_destination.id.to_s => { "status" => "blocked" } },
          checked_at: 2.minutes.from_now
        )
      end

      it "keeps the draft when confirmation uses an older ready report" do
        service.call

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
        expect(WorkflowRun.where(workflowable: publication)).to be_empty
      end
    end
  end
end
