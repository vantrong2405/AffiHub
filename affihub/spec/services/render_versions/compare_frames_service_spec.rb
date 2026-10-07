require "rails_helper"
require "stringio"

RSpec.describe RenderVersions::CompareFramesService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:source_metadata) { { "duration_seconds" => 2.0, "width" => 32, "height" => 32, "has_audio" => true } }
    let(:source_asset) { create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata) }
    let(:render_version) do
      create(:render_version, video_project:, source_asset:, status: "ready", metadata: { "duration_seconds" => 2.0 })
    end
    let(:source_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:render_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:timecodes) { [ 0.0, 1.0 ] }
    let(:service) { described_class.new(render_version_id: render_version.id, timecodes:) }

    before do
      source_asset.file.attach(io: source_file, filename: "source.mp4", content_type: "video/mp4")
      render_version.file.attach(io: render_file, filename: "render.mp4", content_type: "video/mp4")
    end

    after do
      source_file.close
      render_file.close
    end

    context "when requested timecodes are within both videos" do
      it "returns source and render frames with their timestamps" do
        service.call

        expect(service).to be_success
        expect(service.frames.map { |frame| frame.fetch(:timestamp_seconds) }).to eq([ 0.0, 1.0 ])
        expect(service.frames.first.fetch(:source_frame)).to start_with("data:image/jpeg;base64,")
        expect(service.frames.first.fetch(:render_frame)).to start_with("data:image/jpeg;base64,")
      end
    end

    context "when a timecode is at the end of a video" do
      let(:timecodes) { [ 2.0 ] }

      it "returns a validation failure before extracting frames" do
        service.call

        expect(service).not_to be_success
        expect(service.errors.full_messages.to_sentence).to eq("Timecode phải nằm trong thời lượng của cả source và render.")
        expect(service.frames).to eq([])
      end
    end

    context "when FFmpeg cannot extract a render frame" do
      let(:render_file) { StringIO.new("not a video") }

      it "returns an error and keeps both videos unchanged" do
        source_blob = source_asset.file.blob
        render_blob = render_version.file.blob
        service.call

        expect(service).not_to be_success
        expect(service.errors.full_messages.to_sentence).to eq("Không thể tạo khung hình so sánh.")
        expect(source_asset.reload.file.blob).to eq(source_blob)
        expect(render_version.reload.file.blob).to eq(render_blob)
        expect(render_version.status).to eq("ready")
      end
    end
  end
end
