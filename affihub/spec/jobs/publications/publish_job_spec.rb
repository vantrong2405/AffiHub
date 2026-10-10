require "rails_helper"

RSpec.describe Publications::PublishJob, type: :job do
  describe "#perform" do
    it "returns false without resolving a scheduled Publication while auto-publish is paused" do
      schedule_occurrence = create(:schedule_occurrence)
      publication = create(:publication, schedule_occurrence:)
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      AutomationControl.current.update!(auto_publish_paused: true)

      expect(Publications::PublisherResolver).not_to receive(:new)

      expect(described_class.perform_now(workflow_run.id)).to eq(false)
      expect(workflow_run.reload.status).to eq("queued")
    end

    it "returns true from the publisher configured for a YouTube Publication" do
      social_connection = create(:social_connection, provider: "youtube")
      social_destination = create(
        :social_destination,
        social_connection:,
        provider: "youtube"
      )
      publication = create(:publication, social_destination:, status: "approved")
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      publisher = double("configured YouTube publisher", call: true)
      publisher_class = double("Publications::YoutubePublisher", new: publisher)
      stub_const("Publications::YoutubePublisher", publisher_class)

      expect(described_class.perform_now(workflow_run.id)).to eq(true)
      expect(publisher_class).to have_received(:new).with(workflow_run_id: workflow_run.id)
      expect(publisher).to have_received(:call).once
    end

    it "returns true from the publisher configured for a TikTok Publication" do
      social_connection = create(:social_connection, provider: "tiktok")
      social_destination = create(
        :social_destination,
        social_connection:,
        provider: "tiktok"
      )
      publication = create(:publication, social_destination:, status: "approved")
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      publisher = double("configured TikTok publisher", call: true)
      publisher_class = double("Publications::TikTokPublisher", new: publisher)
      stub_const("Publications::TikTokPublisher", publisher_class)

      expect(described_class.perform_now(workflow_run.id)).to eq(true)
      expect(publisher_class).to have_received(:new).with(workflow_run_id: workflow_run.id)
      expect(publisher).to have_received(:call).once
    end

    it "returns true from the publisher configured for an Instagram Publication" do
      social_connection = create(:social_connection, provider: "instagram")
      social_destination = create(
        :social_destination,
        social_connection:,
        provider: "instagram",
        metadata: {
          "page_id" => "page-1",
          "instagram_business_account_id" => "ig-business-1",
          "instagram_account_type" => "BUSINESS"
        }
      )
      publication = create(:publication, social_destination:, status: "approved")
      workflow_run = create(
        :workflow_run,
        workflowable: publication,
        operation: "publication_publish",
        stage: "publish",
        status: "queued"
      )
      publisher = double("configured Instagram publisher", call: true)
      publisher_class = double("Publications::InstagramPublisher", new: publisher)
      stub_const("Publications::InstagramPublisher", publisher_class)

      expect(described_class.perform_now(workflow_run.id)).to eq(true)
      expect(publisher_class).to have_received(:new).with(workflow_run_id: workflow_run.id)
      expect(publisher).to have_received(:call).once
    end
  end
end
