require "rails_helper"

RSpec.describe Publications::ShowService, type: :service do
  describe "#call" do
    it "loads the publication, latest report, and workflow from the selected project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      publication = create(:publication, render_version:, social_destination:)
      preflight_report = create(:preflight_report, render_version:)
      workflow_run = create(:workflow_run, workflowable: publication, operation: "publication_publish", stage: "publish")
      outbound_attempt = create(:outbound_attempt, workflow_run:, stage: "publish")
      service = described_class.new(video_project_id: video_project.id, publication_id: publication.id)

      expect(service.call).to be(true)
      expect(service.video_project).to eq(video_project)
      expect(service.publication).to eq(publication)
      expect(service.latest_preflight_report).to eq(preflight_report)
      expect(service.workflow_run).to eq(workflow_run)
      expect(service.outbound_attempt).to eq(outbound_attempt)
    end

    it "returns not found when the publication belongs to another project" do
      video_project = create(:video_project)
      publication = create(:publication)
      service = described_class.new(video_project_id: video_project.id, publication_id: publication.id)

      expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns every configured YouTube privacy choice before API compliance audit" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_connection = create(:social_connection, provider: "youtube")
      social_destination = create(
        :social_destination,
        social_connection:,
        provider: "youtube"
      )
      publication = create(:publication, render_version:, social_destination:)
      service = described_class.new(video_project_id: video_project.id, publication_id: publication.id)

      expect(service.call).to eq(true)

      expect(service.youtube_privacy_statuses).to eq([ "private", "unlisted", "public" ])
    end

    context "when reviewing a TikTok Publication" do
      let(:video_project) { create(:video_project) }
      let(:render_version) { create(:render_version, video_project:) }
      let(:social_connection) { create(:social_connection, provider: "tiktok") }
      let(:social_destination) do
        create(
          :social_destination,
          social_connection:,
          provider: "tiktok",
          external_id: "creator-1"
        )
      end
      let(:publication) { create(:publication, render_version:, social_destination:) }

      before do
        token_service = double("TikTok access token service", call: true, access_token: "creator-access-token")
        allow(SocialConnections::TikTok::AccessTokenService).to receive(:new)
          .with(social_destination_id: social_destination.id)
          .and_return(token_service)
      end

      it "returns allowed privacy choices and creator-disabled interactions" do
        client = double("TikTok::Client")
        allow(TikTok::Client).to receive(:new).and_return(client)
        allow(client).to receive(:creator_info).and_return(
          "data" => {
            "privacy_level_options" => [ "SELF_ONLY", "PUBLIC_TO_EVERYONE" ],
            "comment_disabled" => true,
            "duet_disabled" => false,
            "stitch_disabled" => true
          },
          "error" => { "code" => "ok" }
        )
        service = described_class.new(video_project_id: render_version.video_project_id, publication_id: publication.id)

        expect(service.call).to eq(true)

        expect(service.tiktok_privacy_levels).to eq([ "SELF_ONLY" ])
        expect(service.tiktok_creator_info_available).to eq(true)
        expect(service.tiktok_disabled_interactions).to eq(
          "comment" => true,
          "duet" => false,
          "stitch" => true
        )
        expect(service.tiktok_cap_status).to eq("unavailable_counter")
      end

      it "returns a creator cap state without claiming a numeric remaining count" do
        client = double("TikTok::Client")
        allow(TikTok::Client).to receive(:new).and_return(client)
        allow(client).to receive(:creator_info).and_return(
          "data" => {},
          "error" => { "code" => "spam_risk_too_many_posts" }
        )
        service = described_class.new(video_project_id: render_version.video_project_id, publication_id: publication.id)

        expect(service.call).to eq(true)

        expect(service.tiktok_cap_status).to eq("creator_cap_reached")
        expect(service.tiktok_privacy_levels).to eq([])
      end

      it "returns the application cap state from the TikTok provider signal" do
        client = double("TikTok::Client")
        allow(TikTok::Client).to receive(:new).and_return(client)
        allow(client).to receive(:creator_info).and_return(
          "data" => {},
          "error" => { "code" => "reached_active_user_cap" }
        )
        service = described_class.new(video_project_id: render_version.video_project_id, publication_id: publication.id)

        expect(service.call).to eq(true)

        expect(service.tiktok_cap_status).to eq("provider_app_cap_reached")
        expect(service.tiktok_privacy_levels).to eq([])
      end

      it "returns unavailable creator settings when the access token cannot be loaded" do
        token_service = double("TikTok access token service", call: false, access_token: nil)
        allow(SocialConnections::TikTok::AccessTokenService).to receive(:new)
          .with(social_destination_id: social_destination.id)
          .and_return(token_service)
        service = described_class.new(video_project_id: render_version.video_project_id, publication_id: publication.id)

        expect(service.call).to eq(true)

        expect(service.tiktok_creator_info_available).to eq(false)
        expect(service.tiktok_privacy_levels).to eq([])
        expect(service.tiktok_disabled_interactions).to eq(
          "comment" => true,
          "duet" => true,
          "stitch" => true
        )
      end

      it "returns unavailable creator settings when interaction values are missing" do
        client = double("TikTok::Client")
        allow(TikTok::Client).to receive(:new).and_return(client)
        allow(client).to receive(:creator_info).and_return(
          "data" => {
            "privacy_level_options" => [ "SELF_ONLY" ],
            "duet_disabled" => false,
            "stitch_disabled" => false
          },
          "error" => { "code" => "ok" }
        )
        service = described_class.new(video_project_id: render_version.video_project_id, publication_id: publication.id)

        expect(service.call).to eq(true)

        expect(service.tiktok_creator_info_available).to eq(false)
        expect(service.tiktok_privacy_levels).to eq([])
        expect(service.tiktok_disabled_interactions).to eq(
          "comment" => true,
          "duet" => true,
          "stitch" => true
        )
      end
    end
  end
end
