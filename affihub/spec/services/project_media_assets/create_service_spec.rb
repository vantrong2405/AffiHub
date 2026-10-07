require "rails_helper"

RSpec.describe ProjectMediaAssets::CreateService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:extension) { "png" }
    let(:content_type) { "image/png" }
    let(:image_tempfile) do
      tempfile = Tempfile.new([ "brand", ".#{extension}" ])
      tempfile.binmode
      tempfile.write(File.binread(Rails.root.join("spec/fixtures/files/brand.#{extension}")))
      tempfile.rewind
      tempfile
    end
    let(:upload) do
      ActionDispatch::Http::UploadedFile.new(
        tempfile: image_tempfile,
        filename: "brand.#{extension}",
        type: content_type
      )
    end
    let(:service) { described_class.new(video_project:, file: upload) }

    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
    after { image_tempfile.close! }

    it "returns a project-owned image asset with the verified file attached" do
      service.call

      expect(service).to be_success
      expect(service.project_media_asset.video_project).to eq(video_project)
      expect(service.project_media_asset.file).to be_attached
      expect(service.project_media_asset.file.content_type).to eq(content_type)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }).to eq([ ActiveStorage::AnalyzeJob ])
    end

    context "when the image is JPEG" do
      let(:extension) { "jpg" }
      let(:content_type) { "image/jpeg" }

      it "returns success for a valid JPEG" do
        service.call

        expect(service).to be_success
        expect(service.project_media_asset.file.content_type).to eq("image/jpeg")
      end
    end

    context "when the image is WebP" do
      let(:extension) { "webp" }
      let(:content_type) { "image/webp" }

      it "returns success for a valid WebP" do
        service.call

        expect(service).to be_success
        expect(service.project_media_asset.file.content_type).to eq("image/webp")
      end
    end

    it "returns a validation failure for a MIME type outside PNG, JPEG, and WebP" do
      file = ActionDispatch::Http::UploadedFile.new(tempfile: upload.tempfile, filename: "brand.png", type: "text/plain")
      invalid_service = described_class.new(video_project:, file:)

      invalid_service.call

      expect(invalid_service).not_to be_success
      expect(ProjectMediaAsset.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    it "returns a validation failure when the image signature conflicts with its MIME type" do
      file = ActionDispatch::Http::UploadedFile.new(tempfile: upload.tempfile, filename: "brand.jpg", type: "image/jpeg")
      invalid_service = described_class.new(video_project:, file:)

      invalid_service.call

      expect(invalid_service).not_to be_success
      expect(ProjectMediaAsset.count).to eq(0)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
    end

    context "when the file exceeds the default size limit" do
      let(:large_image) do
        tempfile = Tempfile.new([ "large-brand", ".png" ])
        tempfile.binmode
        tempfile.write("\x89PNG\r\n\x1A\n")
        tempfile.truncate(20_971_521)
        tempfile.rewind
        ActionDispatch::Http::UploadedFile.new(tempfile:, filename: "large-brand.png", type: "image/png")
      end
      let(:service) { described_class.new(video_project:, file: large_image) }

      after { large_image.tempfile.close! }

      it "returns a validation failure before creating an asset" do
        service.call

        expect(service).not_to be_success
        expect(ProjectMediaAsset.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
