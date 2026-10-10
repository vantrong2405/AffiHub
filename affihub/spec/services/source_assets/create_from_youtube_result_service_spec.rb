# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAssets::CreateFromYoutubeResultService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:discovery_metadata) do
      create(
        :youtube_discovery_metadata,
        video_id: "video-123",
        title: "Home cooking",
        channel_title: "Kitchen",
        fetched_at: 1.hour.ago
      )
    end
    let(:source_discovery) { create(:source_discovery, video_project:) }
    let!(:source_discovery_result) do
      create(
        :source_discovery_result,
        source_discovery:,
        youtube_discovery_metadata: discovery_metadata
      )
    end
    let(:service) do
      described_class.new(
        video_project:,
        source_discovery_id: source_discovery.id,
        discovery_metadata_id: discovery_metadata.id,
        rights_confirmed: true
      )
    end

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      allow(Resolv).to receive(:getaddresses)
        .with("www.youtube.com")
        .and_return([ "142.251.35.4" ])
    end

    it "creates a source from the selected result and queues its download" do
      expect { service.call }.to change(SourceAsset, :count).by(1)

      expect(service).to be_success
      expect(service.source_asset).to have_attributes(
        source_url: "https://www.youtube.com/watch?v=video-123",
        status: "pending",
        provenance: include(
          "platform" => "youtube",
          "method" => "discovery_selection",
          "video_id" => "video-123"
        )
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
        .to eq([ SourceAssets::DownloadJob ])
    end

    context "when the selected result metadata reaches 30 days" do
      let(:discovery_metadata) do
        create(:youtube_discovery_metadata, video_id: "video-123", fetched_at: 30.days.ago)
      end

      it "returns failure without creating a source or queuing a download" do
        expect { service.call }.not_to change(SourceAsset, :count)

        expect(service).not_to be_success
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the user has not confirmed the rights warning" do
      let(:service) do
        described_class.new(
          video_project:,
          source_discovery_id: source_discovery.id,
          discovery_metadata_id: discovery_metadata.id,
          rights_confirmed: "0"
        )
      end

      it "returns failure without creating a source or queuing a download" do
        expect { service.call }.not_to change(SourceAsset, :count)

        expect(service).not_to be_success
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
