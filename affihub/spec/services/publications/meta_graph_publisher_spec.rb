require "rails_helper"

RSpec.describe Publications::MetaGraphPublisher, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version, status: "ready") }
    let(:publication) do
      create(
        :publication,
        render_version:,
        social_destination: create(:social_destination, external_id: "page-1"),
        status: "approved"
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
    let(:graph_api_url) do
      configuration = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers).fetch(:facebook)
      "#{configuration.fetch(:graph_api_base_url)}/#{configuration.fetch(:api_version)}"
    end
    let(:page_reel_request) do
      stub_request(:post, "#{graph_api_url}/page-1/video_reels").with(
        query: { "upload_phase" => "start", "access_token" => "page-access-token" }
      ).to_return(body: { video_id: "video-1", upload_url: "https://rupload.facebook.com/upload/video-1" }.to_json)
    end
    let(:finish_reel_request) do
      stub_request(:post, "#{graph_api_url}/page-1/video_reels").with(
        query: {
          "upload_phase" => "finish",
          "video_id" => "video-1",
          "video_state" => "PUBLISHED",
          "description" => publication.caption,
          "access_token" => "page-access-token"
        }
      ).to_return(body: { success: true }.to_json)
    end
    let(:upload_request) do
      stub_request(:post, "https://rupload.facebook.com/upload/video-1").to_return(
        body: { success: true }.to_json
      )
    end
    let(:status_request) do
      stub_request(:get, "#{graph_api_url}/video-1").with(
        query: { "fields" => "status,permalink_url", "access_token" => "page-access-token" }
      ).to_return(
        body: {
          status: {
            video_status: "ready",
            publishing_phase: { status: "complete" }
          },
          permalink_url: "https://facebook.com/reel/1"
        }.to_json
      )
    end
    let(:service) { described_class.new(workflow_run_id: workflow_run.id) }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      publication.render_version.file.attach(
        io: StringIO.new("video bytes"),
        filename: "render.mp4",
        content_type: "video/mp4"
      )
      page_reel_request
      finish_reel_request
      upload_request
      status_request
    end

    it "marks the Publication published after Meta confirms the final Reel status" do
      expect(service.call).to be(true)

      expect(publication.reload.status).to eq("published")
      expect(publication.platform_post_id).to eq("video-1")
      expect(publication.permalink).to eq("https://facebook.com/reel/1")
      expect(publication.published_at).to be_present
    end

    context "when Meta has not confirmed the final Reel status" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").with(
          query: { "fields" => "status,permalink_url", "access_token" => "page-access-token" }
        ).to_return(
          body: {
            status: {
              video_status: "ready",
              publishing_phase: { status: "in_progress" }
            }
          }.to_json
        )
      end

      it "keeps the Publication out of the published state" do
        expect { service.call }.to have_enqueued_job(Publications::PublishJob).with(workflow_run.id)

        expect(publication.reload.status).to eq("processing")
        expect(publication.published_at).to be_nil
        expect(publication.permalink).to be_nil
        expect(workflow_run.reload.status).to eq("queued")
      end
    end

    context "when Meta confirms publishing but does not return a permalink" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").with(
          query: { "fields" => "status,permalink_url", "access_token" => "page-access-token" }
        ).to_return(
          body: {
            status: {
              video_status: "ready",
              publishing_phase: { status: "complete" }
            }
          }.to_json
        )
      end

      it "does not mark the Publication published without a permalink" do
        expect(service.call).to be(true)

        expect(publication.reload.status).to eq("processing")
        expect(publication.published_at).to be_nil
        expect(publication.permalink).to be_nil
      end
    end

    context "when Meta returns a permalink outside Facebook" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").with(
          query: { "fields" => "status,permalink_url", "access_token" => "page-access-token" }
        ).to_return(
          body: {
            status: {
              video_status: "ready",
              publishing_phase: { status: "complete" }
            },
            permalink_url: "https://attacker.example/reel/1"
          }.to_json
        )
      end

      it "does not store or publish the untrusted permalink" do
        expect(service.call).to be(true)

        expect(publication.reload.status).to eq("processing")
        expect(publication.permalink).to be_nil
        expect(publication.published_at).to be_nil
      end
    end

    context "when a previous publish attempt has an unknown outcome" do
      let(:publication) do
        create(
          :publication,
          social_destination: create(:social_destination, external_id: "page-1"),
          status: "outcome_unknown"
        )
      end
      let(:workflow_run) do
        create(
          :workflow_run,
          workflowable: publication,
          operation: "publication_publish",
          stage: "publish",
          status: "reconciliation_required"
        )
      end
      let!(:outbound_attempt) do
        create(
          :outbound_attempt,
          workflow_run:,
          status: "outcome_unknown",
          sender_stopped_at: 2.minutes.ago,
          request_timeout_at: 1.minute.ago
        )
      end

      it "does not send another Meta request" do
        expect(service.call).to be(false)

        expect(publication.reload.status).to eq("outcome_unknown")
        expect(outbound_attempt.reload.status).to eq("outcome_unknown")
        expect(page_reel_request).not_to have_been_requested
        expect(finish_reel_request).not_to have_been_requested
        expect(upload_request).not_to have_been_requested
        expect(status_request).not_to have_been_requested
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when Meta's final status request times out" do
      let(:status_request) do
        stub_request(:get, "#{graph_api_url}/video-1").with(
          query: { "fields" => "status,permalink_url", "access_token" => "page-access-token" }
        ).to_raise(Net::ReadTimeout)
      end

      it "keeps the Publication unresolved and does not retry the publish request" do
        expect(service.call).to be(false)

        expect(publication.reload.status).to eq("outcome_unknown")
        expect(workflow_run.reload.status).to eq("reconciliation_required")
        expect(workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
        expect(page_reel_request).to have_been_requested.once
        expect(finish_reel_request).to have_been_requested.once
        expect(status_request).to have_been_requested.once
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when Meta reports a transient error after the publish request" do
      let(:finish_reel_request) do
        stub_request(:post, "#{graph_api_url}/page-1/video_reels").with(
          query: {
            "upload_phase" => "finish",
            "video_id" => "video-1",
            "video_state" => "PUBLISHED",
            "description" => publication.caption,
            "access_token" => "page-access-token"
          }
        ).to_return(body: { error: { code: 2, message: "Temporary failure" } }.to_json)
      end

      it "keeps the Publication unresolved and does not retry the publish request" do
        expect(service.call).to be(false)

        expect(publication.reload.status).to eq("outcome_unknown")
        expect(workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
        expect(finish_reel_request).to have_been_requested.once
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
