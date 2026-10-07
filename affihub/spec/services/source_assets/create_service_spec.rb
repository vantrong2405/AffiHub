require "rails_helper"

RSpec.describe SourceAssets::CreateService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:upload_tempfile) do
      tempfile = Tempfile.new([ "local-source", ".mp4" ])
      tempfile.binmode
      tempfile.write(File.binread(Rails.root.join("spec/fixtures/files/local_source.mp4")))
      tempfile.rewind
      tempfile
    end
    let(:upload) do
      ActionDispatch::Http::UploadedFile.new(
        tempfile: upload_tempfile,
        filename: "local_source.mp4",
        type: "video/mp4"
      )
    end
    let(:service) { described_class.new(video_project:, file: upload) }

    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
    after { upload_tempfile.close! }

    it "returns a pending attached source and queues only media inspection" do
      service.call

      expect(service).to be_success
      expect(service.source_asset.video_project).to eq(video_project)
      expect(service.source_asset.status).to eq("pending")
      expect(service.source_asset.file).to be_attached
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }).to eq([ SourceAssets::InspectJob ])
    end

    it "returns a pending source for a valid MOV file" do
      tempfile = Tempfile.new([ "local-source", ".mov" ])
      tempfile.binmode
      tempfile.write(File.binread(Rails.root.join("spec/fixtures/files/local_source.mov")))
      tempfile.rewind
      begin
        file = ActionDispatch::Http::UploadedFile.new(tempfile:, filename: "local_source.mov", type: "video/quicktime")
        service = described_class.new(video_project:, file:)
        service.call

        expect(service).to be_success
        expect(service.source_asset.status).to eq("pending")
      ensure
        tempfile.close!
      end
    end

    it "returns a validation error when the declared MIME type is unsupported" do
      file = ActionDispatch::Http::UploadedFile.new(tempfile: upload.tempfile, filename: "source.mp4", type: "text/plain")
      service = described_class.new(video_project:, file:)
      service.call

      expect(service).not_to be_success
      expect(SourceAsset.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end

    it "returns a validation error when the media signature is not MP4 or MOV" do
      file = ActionDispatch::Http::UploadedFile.new(tempfile: StringIO.new("plain text"), filename: "source.mp4", type: "video/mp4")
      service = described_class.new(video_project:, file:)
      service.call

      expect(service).not_to be_success
      expect(SourceAsset.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
    end

    context "when the file exceeds the default size limit" do
      let(:large_file) do
        tempfile = Tempfile.new([ "large-source", ".mp4" ])
        tempfile.binmode
        tempfile.write("00000018ftypisom")
        tempfile.truncate(1_073_741_825)
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(tempfile:, filename: "large-source.mp4", type: "video/mp4")
      end
      let(:service) { described_class.new(video_project:, file: large_file) }

      after { large_file.tempfile.close! }

      it "returns a validation error before attaching or queueing the file" do
        service.call

        expect(service).not_to be_success
        expect(SourceAsset.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
      end
    end

    context "when the user confirms a YouTube owner export" do
      let(:provenance) { { "platform" => "youtube", "method" => "owner_export", "source" => "youtube_studio" } }
      let(:service) { described_class.new(video_project:, file: upload, provenance:) }

      it "returns a source with provenance and queues no downloader" do
        service.call

        expect(service.source_asset.provenance).to eq(provenance)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }).to eq([ SourceAssets::InspectJob ])
        expect(WebMock).not_to have_requested(:any, %r{\Ahttps://})
      end
    end
  end
end
