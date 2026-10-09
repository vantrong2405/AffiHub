require "rails_helper"

RSpec.describe "Publication pages", type: :request do
  describe "POST /video_projects/:video_project_id/publications" do
    it "creates one draft per selected destination with its own caption" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready")
      first_destination = create(:social_destination, name: "Page Một")
      second_destination = create(:social_destination, name: "Page Hai")
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ first_destination.id, second_destination.id ],
        destination_results: {
          first_destination.id.to_s => { "status" => "ready" },
          second_destination.id.to_s => { "status" => "ready" }
        }
      )

      expect do
        post video_project_publications_path(video_project), params: {
          publication: {
            render_version_id: render_version.id,
            preflight_report_id: preflight_report.id,
            destination_ids: [ first_destination.id, second_destination.id ],
            destination_captions: {
              first_destination.id.to_s => "Caption Page Một",
              second_destination.id.to_s => "Caption Page Hai"
            }
          }
        }
      end.to change(Publication, :count).by(2)

      expect(response).to redirect_to(video_project_publications_path(video_project))
      expect(Publication.find_by!(social_destination: first_destination).caption).to eq("Caption Page Một")
      expect(Publication.find_by!(social_destination: second_destination).caption).to eq("Caption Page Hai")
    end
  end

  describe "PATCH /video_projects/:video_project_id/publications/:id" do
    it "updates the caption of a draft in the selected project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      publication = create(:publication, render_version:, caption: "Caption cũ")

      patch video_project_publication_path(video_project, publication), params: {
        publication: { caption: "Caption mới" }
      }

      expect(response).to redirect_to(video_project_publication_path(video_project, publication))
      expect(publication.reload.caption).to eq("Caption mới")
    end

    it "returns not found when the publication belongs to another project" do
      video_project = create(:video_project)
      publication = create(:publication)

      patch video_project_publication_path(video_project, publication), params: {
        publication: { caption: "Caption mới" }
      }

      expect(response).to have_http_status(:not_found)
    end

    it "persists TikTok consent using the selected creator and render records" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_connection = create(
        :social_connection,
        provider: "tiktok",
        external_user_id: "creator-1"
      )
      social_destination = create(
        :social_destination,
        social_connection:,
        provider: "tiktok",
        external_id: "creator-1"
      )
      publication = create(:publication, render_version:, social_destination:)
      token_service = double("TikTok access token service", call: true, access_token: "creator-access-token")
      tiktok_client = double("TikTok::Client")
      allow(SocialConnections::TikTok::AccessTokenService).to receive(:new)
        .with(social_destination_id: social_destination.id)
        .and_return(token_service)
      allow(TikTok::Client).to receive(:new).and_return(tiktok_client)
      allow(tiktok_client).to receive(:creator_info).with(access_token: "creator-access-token").and_return(
        "data" => {
          "privacy_level_options" => [ "SELF_ONLY" ],
          "comment_disabled" => false,
          "duet_disabled" => false,
          "stitch_disabled" => false
        },
        "error" => { "code" => "ok" }
      )

      patch video_project_publication_path(video_project, publication), params: {
        publication: {
          caption: "Caption TikTok",
          consent_attributes: {
            privacy_level: "SELF_ONLY",
            allow_comment: "0",
            allow_duet: "0",
            allow_stitch: "0",
            brand_organic_toggle: "0",
            brand_content_toggle: "0",
            is_aigc: "1",
            creator_account_private: "1",
            music_usage_confirmed: "1",
            tiktok_creator_id: "forged-creator"
          }
        }
      }

      expect(response).to redirect_to(video_project_publication_path(video_project, publication))
      expect(publication.reload.consent_snapshot.slice(
        "privacy_level",
        "allow_comment",
        "allow_duet",
        "allow_stitch",
        "brand_organic_toggle",
        "brand_content_toggle",
        "is_aigc",
        "creator_account_private",
        "music_usage_confirmed",
        "tiktok_social_connection_id",
        "tiktok_creator_id",
        "tiktok_render_version_id",
        "tiktok_publication_id"
      )).to eq(
        "privacy_level" => "SELF_ONLY",
        "allow_comment" => false,
        "allow_duet" => false,
        "allow_stitch" => false,
        "brand_organic_toggle" => false,
        "brand_content_toggle" => false,
        "is_aigc" => true,
        "creator_account_private" => true,
        "music_usage_confirmed" => true,
        "tiktok_social_connection_id" => social_connection.id,
        "tiktok_creator_id" => "creator-1",
        "tiktok_render_version_id" => render_version.id,
        "tiktok_publication_id" => publication.id
      )
    end
  end

  describe "POST /video_projects/:video_project_id/publications/:id/confirm" do
    it "approves and queues a draft with a ready preflight report" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      publication = create(:publication, render_version:, social_destination:)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )

      expect do
        post confirm_video_project_publication_path(video_project, publication), params: {
          publication: { preflight_report_id: preflight_report.id }
        }
      end.to have_enqueued_job(Publications::PublishJob)

      expect(response).to redirect_to(video_project_publication_path(video_project, publication))
      expect(publication.reload.status).to eq("approved")
    end

    it "keeps a draft when the latest report blocks its destination" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      publication = create(:publication, render_version:, social_destination:)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "blocked" } }
      )

      post confirm_video_project_publication_path(video_project, publication), params: {
        publication: { preflight_report_id: preflight_report.id }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(publication.reload.status).to eq("draft")
      expect(WorkflowRun.where(workflowable: publication)).to be_empty
    end

    it "returns not found when the publication belongs to another project" do
      video_project = create(:video_project)
      publication = create(:publication)

      post confirm_video_project_publication_path(video_project, publication), params: {
        publication: { preflight_report_id: create(:preflight_report).id }
      }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /video_projects/:video_project_id/publications/:id/resolve_outcome" do
    it "records the operator's evidence while keeping an unknown outcome unresolved" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      publication = create(:publication, render_version:, status: "outcome_unknown")
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "outcome_unknown"
      )
      create(
        :outbound_attempt,
        workflow_run:,
        status: "outcome_unknown",
        sender_stopped_at: 2.minutes.ago,
        request_timeout_at: 1.minute.ago
      )

      post resolve_outcome_video_project_publication_path(video_project, publication), params: {
        publication: {
          decision: "unknown",
          evidence: "Page chưa cập nhật",
          actor_reference: "operator-1"
        }
      }

      expect(response).to redirect_to(video_project_publication_path(video_project, publication))
      expect(publication.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.workflow_audit_events.sole.details).to include(
        "decision" => "unknown",
        "evidence" => "Page chưa cập nhật",
        "actor_reference" => "local-operator"
      )
    end

    it "returns not found when the publication belongs to another project" do
      video_project = create(:video_project)
      publication = create(:publication, status: "outcome_unknown")

      post resolve_outcome_video_project_publication_path(video_project, publication), params: {
        publication: { decision: "unknown", evidence: "Page chưa cập nhật" }
      }

      expect(response).to have_http_status(:not_found)
    end
  end
end
