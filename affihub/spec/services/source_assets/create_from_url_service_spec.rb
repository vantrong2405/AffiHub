# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAssets::CreateFromUrlService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:url) { "https://www.youtube.com/watch?v=video-123" }
    let(:service) do
      described_class.new(video_project:, url:, rights_confirmed: true)
    end

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      allow(Resolv).to receive(:getaddresses)
        .with("www.youtube.com")
        .and_return([ "142.251.35.4" ])
    end

    it "creates a pending source and queues one background download" do
      expect { service.call }.to change(SourceAsset, :count).by(1)

      expect(service).to be_success
      expect(service.source_asset).to have_attributes(
        source_url: url,
        status: "pending",
        provenance: include("platform" => "youtube", "method" => "url_import")
      )
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
        .to eq([ SourceAssets::DownloadJob ])
    end

    context "when the user has not confirmed the rights warning" do
      let(:service) do
        described_class.new(video_project:, url:, rights_confirmed: false)
      end

      it "returns failure without creating a source or queuing a download" do
        expect { service.call }.not_to change(SourceAsset, :count)

        expect(service).not_to be_success
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the URL does not use HTTPS" do
      let(:url) { "http://www.youtube.com/watch?v=video-123" }

      it "returns failure without creating a source or queuing a download" do
        expect { service.call }.not_to change(SourceAsset, :count)

        expect(service).not_to be_success
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the host is outside the configured allowlist" do
      let(:url) { "https://videos.example.test/watch/123" }

      it "returns failure without resolving or queuing the URL" do
        expect { service.call }.not_to change(SourceAsset, :count)

        expect(service).not_to be_success
        expect(Resolv).not_to have_received(:getaddresses)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
