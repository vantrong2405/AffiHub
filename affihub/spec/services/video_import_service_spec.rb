# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe VideoImportService do
  let(:video_bytes) { "local video bytes" }
  let(:content_type) { "video/mp4" }
  let(:temporary_file) { Tempfile.new(["local-video", ".mp4"]) }
  let(:uploaded_file) do
    temporary_file.binmode
    temporary_file.write(video_bytes)
    temporary_file.rewind
    Rack::Test::UploadedFile.new(temporary_file.path, content_type)
  end

  after do
    temporary_file.close!
  end

  it "creates a local project, source, and render without platform identifiers" do
    service = described_class.new(file: uploaded_file)
    service.call

    expect(service.success?).to eq(true)
    expect(service.video_project.status).to eq("draft")
    expect(service.source_asset.video_project).to eq(service.video_project)
    expect(service.source_asset.file.download).to eq(video_bytes)
    expect(service.render_version.source_asset).to eq(service.source_asset)
    expect(service.render_version.status).to eq("ready")
    expect(service.render_version.file.download).to eq(video_bytes)
    expect(service.render_version.metadata).to eq({})
  end

  context "when the uploaded file is not an accepted video type" do
    let(:content_type) { "video/webm" }

    it "returns a validation error without creating project records" do
      service = described_class.new(file: uploaded_file)
      service.call

      expect(service).not_to be_success
      expect(service.errors[:file]).to be_present
      expect(VideoProject.count).to eq(0)
    end
  end
end
