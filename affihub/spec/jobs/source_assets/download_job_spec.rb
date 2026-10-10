# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe SourceAssets::DownloadJob, type: :job do
  describe "#perform" do
    let(:source_asset) do
      create(
        :source_asset,
        source_type: "url_download",
        source_url: "https://www.youtube.com/watch?v=video-123",
        provenance: { "platform" => "youtube", "method" => "url_import" }
      )
    end
    let(:binary_directory) { Dir.mktmpdir("fake-yt-dlp") }
    let(:script) do
      <<~SCRIPT
        #!/bin/sh
        echo 'ERROR: unsupported URL' >&2
        exit 1
      SCRIPT
    end
    let(:original_path) { ENV.fetch("PATH") }

    before do
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      File.write(File.join(binary_directory, "yt-dlp"), script)
      FileUtils.chmod(0o755, File.join(binary_directory, "yt-dlp"))
      ENV["PATH"] = "#{binary_directory}:#{original_path}"
    end

    after do
      ENV["PATH"] = original_path
      FileUtils.remove_entry(binary_directory)
    end

    context "when ten download starts are inside the rolling hour" do
      let!(:recent_download_slots) do
        create_list(:source_download_slot, 10, started_at: 30.minutes.ago)
      end

      it "marks the source as waiting for its slot and schedules it for the next available slot" do
        described_class.perform_now(source_asset.id)
        queued_job = ActiveJob::Base.queue_adapter.enqueued_jobs.sole

        expect(source_asset.reload.status).to eq("waiting_for_download_slot")
        expect(queued_job[:job]).to eq(described_class)
        expect(queued_job[:args]).to eq([ source_asset.id ])
        expect(Time.at(queued_job[:at]))
          .to be_within(1.second).of(recent_download_slots.first.started_at + 60.minutes)
      end
    end

    context "when yt-dlp exceeds its configured timeout" do
      let(:script) do
        <<~SCRIPT
          #!/bin/sh
          sleep 10
        SCRIPT
      end

      it "marks the source failed with local import guidance and does not retry" do
        described_class.perform_now(source_asset.id)

        expect(source_asset.reload.status).to eq("failed")
        expect(source_asset.download_error).to include("MP4 hoặc MOV")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the source platform rate-limits yt-dlp" do
      let(:script) do
        <<~SCRIPT
          #!/bin/sh
          echo 'ERROR: HTTP Error 429: Too Many Requests' >&2
          exit 1
        SCRIPT
      end

      it "marks the source rate-limited and does not enqueue an automatic retry" do
        described_class.perform_now(source_asset.id)

        expect(source_asset.reload.download_error_code).to eq("rate_limited")
        expect(source_asset.download_error).to include("MP4 hoặc MOV")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when yt-dlp downloads the source successfully" do
      it "attaches the downloaded file and queues media inspection" do
        downloader = instance_double(YtDlp::Client)
        allow(YtDlp::Client).to receive(:new).and_return(downloader)
        allow(downloader).to receive(:download) do |url:, output_path:|
          File.write(output_path.sub("%(ext)s", "mp4"), "downloaded video")
        end

        described_class.perform_now(source_asset.id)

        expect(source_asset.reload.status).to eq("pending")
        expect(source_asset.file).to be_attached
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] })
          .to eq([ SourceAssets::InspectJob ])
        expect(downloader).to have_received(:download)
          .with(url: source_asset.source_url, output_path: a_string_including("%(ext)s"))
      end
    end

    context "when yt-dlp cannot retrieve the selected video" do
      it "marks the source failed and explains the local import fallback" do
        described_class.perform_now(source_asset.id)

        expect(source_asset.reload.status).to eq("failed")
        expect(source_asset.download_error).to include("MP4 hoặc MOV")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
