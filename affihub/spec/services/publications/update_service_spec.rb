require "rails_helper"

RSpec.describe Publications::UpdateService, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version) }
    let(:social_destination) { create(:social_destination) }
    let(:publication) do
      create(
        :publication,
        render_version:,
        social_destination:,
        caption: "Caption ban đầu"
      )
    end

    it "updates the caption while keeping the draft render and destination" do
      service = described_class.new(
        video_project_id: render_version.video_project_id,
        publication_id: publication.id,
        caption: "Caption đã sửa"
      )

      service.call

      expect(service).to be_success
      expect(publication.reload).to have_attributes(
        caption: "Caption đã sửa",
        render_version:,
        social_destination:
      )
    end

    it "persists YouTube upload consent bound to the server-selected account, channel, render, and Publication" do
      social_connection = create(
        :social_connection,
        provider: "youtube",
        external_user_id: "google-sub-1"
      )
      youtube_destination = create(
        :social_destination,
        social_connection:,
        provider: "youtube",
        external_id: "channel-1"
      )
      youtube_publication = create(
        :publication,
        render_version:,
        social_destination: youtube_destination
      )
      service = described_class.new(
        video_project_id: render_version.video_project_id,
        publication_id: youtube_publication.id,
        caption: "Caption YouTube",
        consent_attributes: {
          "upload_terms_confirmed" => "1",
          "privacy_status" => "private",
          "self_declared_made_for_kids" => "0",
          "contains_synthetic_media" => "1",
          "youtube_account_id" => "forged-account",
          "youtube_channel_id" => "forged-channel",
          "render_version_id" => "forged-render",
          "publication_id" => "forged-publication"
        }
      )

      expect(service.call).to eq(true)

      expect(youtube_publication.reload.consent_snapshot.slice(
        "upload_terms_confirmed",
        "youtube_account_id",
        "youtube_channel_id",
        "render_version_id",
        "publication_id",
        "privacy_status",
        "self_declared_made_for_kids",
        "contains_synthetic_media"
      )).to eq(
        "upload_terms_confirmed" => true,
        "youtube_account_id" => "google-sub-1",
        "youtube_channel_id" => "channel-1",
        "render_version_id" => render_version.id,
        "publication_id" => youtube_publication.id,
        "privacy_status" => "private",
        "self_declared_made_for_kids" => false,
        "contains_synthetic_media" => true
      )
      expect(youtube_publication.consent_snapshot.fetch("confirmed_at")).to be_present
    end

    it "persists TikTok consent bound to the server-selected creator, render, and Publication" do
      tiktok_connection = create(
        :social_connection,
        provider: "tiktok",
        external_user_id: "creator-1"
      )
      tiktok_destination = create(
        :social_destination,
        social_connection: tiktok_connection,
        provider: "tiktok",
        external_id: "creator-1"
      )
      tiktok_publication = create(
        :publication,
        render_version:,
        social_destination: tiktok_destination
      )
      service = described_class.new(
        video_project_id: render_version.video_project_id,
        publication_id: tiktok_publication.id,
        caption: "Caption TikTok",
        consent_attributes: {
          "privacy_level" => "SELF_ONLY",
          "allow_comment" => "0",
          "allow_duet" => "0",
          "allow_stitch" => "0",
          "brand_organic_toggle" => "0",
          "brand_content_toggle" => "0",
          "is_aigc" => "1",
          "creator_account_private" => "1",
          "music_usage_confirmed" => "1",
          "tiktok_social_connection_id" => "forged-connection",
          "tiktok_creator_id" => "forged-creator",
          "tiktok_render_version_id" => "forged-render",
          "tiktok_publication_id" => "forged-publication"
        }
      )

      expect(service.call).to eq(true)

      snapshot = tiktok_publication.reload.consent_snapshot
      expect(snapshot.except("tiktok_confirmed_at")).to eq(
        "privacy_level" => "SELF_ONLY",
        "allow_comment" => false,
        "allow_duet" => false,
        "allow_stitch" => false,
        "brand_organic_toggle" => false,
        "brand_content_toggle" => false,
        "is_aigc" => true,
        "creator_account_private" => true,
        "music_usage_confirmed" => true,
        "tiktok_social_connection_id" => tiktok_connection.id,
        "tiktok_creator_id" => "creator-1",
        "tiktok_render_version_id" => render_version.id,
        "tiktok_publication_id" => tiktok_publication.id
      )
      expect(snapshot.fetch("tiktok_confirmed_at")).to be_present
    end

    context "when updating consent for a scheduled TikTok Publication" do
      it "persists the new Schedule snapshot and keeps its Schedule binding" do
        tiktok_connection = create(
          :social_connection,
          provider: "tiktok",
          external_user_id: "creator-1"
        )
        tiktok_destination = create(
          :social_destination,
          social_connection: tiktok_connection,
          provider: "tiktok",
          external_id: "creator-1"
        )
        schedule = create(:schedule, render_version:, recurrence: "daily", status: "paused")
        schedule_occurrence = create(:schedule_occurrence, schedule:, status: "dispatched")
        original_schedule_snapshot = {
          "privacy_level" => "SELF_ONLY",
          "allow_comment" => true,
          "allow_duet" => false,
          "allow_stitch" => false,
          "brand_organic_toggle" => false,
          "brand_content_toggle" => false,
          "is_aigc" => true,
          "creator_account_private" => true,
          "music_usage_confirmed" => true,
          "tiktok_social_connection_id" => tiktok_connection.id,
          "tiktok_creator_id" => "creator-1",
          "tiktok_schedule_id" => schedule.id
        }
        schedule_destination = create(
          :schedule_destination,
          schedule:,
          social_destination: tiktok_destination,
          consent_snapshot: original_schedule_snapshot
        )
        scheduled_publication = create(
          :publication,
          render_version:,
          social_destination: tiktok_destination,
          schedule_occurrence:,
          status: "draft",
          consent_snapshot: original_schedule_snapshot.merge(
            "tiktok_render_version_id" => render_version.id,
            "tiktok_publication_id" => 41
          )
        )
        service = described_class.new(
          video_project_id: render_version.video_project_id,
          publication_id: scheduled_publication.id,
          caption: "Caption TikTok đã xác nhận lại",
          consent_attributes: {
            "privacy_level" => "SELF_ONLY",
            "allow_comment" => "0",
            "allow_duet" => "0",
            "allow_stitch" => "0",
            "brand_organic_toggle" => "0",
            "brand_content_toggle" => "0",
            "is_aigc" => "1",
            "creator_account_private" => "1",
            "music_usage_confirmed" => "1"
          }
        )

        expect(service.call).to eq(true)

        expect(scheduled_publication.reload.consent_snapshot.fetch("tiktok_schedule_id")).to eq(schedule.id)
        expect(schedule_destination.reload.consent_snapshot.slice(
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
          "tiktok_schedule_id"
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
          "tiktok_social_connection_id" => tiktok_connection.id,
          "tiktok_creator_id" => "creator-1",
          "tiktok_schedule_id" => schedule.id
        )
      end
    end

    context "when a publish attempt has already started" do
      let(:publication) do
        create(
          :publication,
          render_version:,
          social_destination:,
          caption: "Caption ban đầu",
          status: "uploading"
        )
      end

      it "returns failure and keeps the Publication unchanged" do
        service = described_class.new(
          video_project_id: render_version.video_project_id,
          publication_id: publication.id,
          caption: "Caption đã sửa"
        )

        service.call

        expect(service).not_to be_success
        expect(publication.reload.caption).to eq("Caption ban đầu")
      end
    end
  end
end
