require "rails_helper"
require "tmpdir"

RSpec.describe SourceAssets::InspectService, type: :service do
  describe "#call" do
    let(:provenance) { { "platform" => "local", "method" => "local_upload" } }
    let(:source_asset) { create(:source_asset, provenance:) }
    let(:media_file) { File.open(Rails.root.join("spec/fixtures/files/local_source.mp4")) }
    let(:filename) { "local_source.mp4" }
    let(:service) { described_class.new(source_asset_id: source_asset.id) }
    let(:sentinel) { Rails.root.join("tmp/ffprobe_command_injection") }

    before do
      source_asset.file.attach(io: media_file, filename:, content_type: "video/mp4")
      FileUtils.rm_f(sentinel)
    end

    after do
      media_file.close
      FileUtils.rm_f(sentinel)
    end

    it "returns persisted probe metadata and marks a valid source ready" do
      service.call

      expect(source_asset.reload.status).to eq("ready")
      expect(source_asset.media_metadata).to eq({
        "duration_seconds" => 1.0,
        "file_size_bytes" => source_asset.file.byte_size,
        "video_codec" => "h264",
        "width" => 32,
        "height" => 32,
        "frame_rate" => "30/1",
        "has_audio" => true,
        "audio_codec" => "aac"
      })
    end

    it "returns a failed source with a stable diagnostic when ffprobe cannot read it" do
      source_asset.file.attach(io: StringIO.new("00000018ftypisombroken"), filename:, content_type: "video/mp4")
      service.call

      expect(source_asset.reload.status).to eq("failed")
      expect(source_asset.inspection_error).to eq("Không thể đọc metadata video. Hãy chọn file MP4/MOV hợp lệ.")
      expect(source_asset.file).to be_attached
    end

    it "returns without executing shell syntax from the uploaded filename" do
      media_file.rewind
      source_asset.file.attach(
        io: media_file,
        filename: "source.mp4; touch #{sentinel};#",
        content_type: "video/mp4"
      )
      service.call

      expect(source_asset.reload.status).to eq("ready")
      expect(File.exist?(sentinel)).to eq(false)
    end

    context "when the source is exported by its owner from YouTube" do
      let(:provenance) { { "platform" => "youtube", "method" => "owner_export", "source" => "youtube_studio" } }

      it "returns the same provenance after media inspection" do
        service.call

        expect(source_asset.reload.provenance).to eq(provenance)
      end
    end

    context "when ffprobe exceeds its timeout" do
      let(:ffprobe_directory) { Dir.mktmpdir }
      let(:original_path) { ENV.fetch("PATH") }

      before do
        executable = File.join(ffprobe_directory, "ffprobe")
        File.write(executable, "#!/bin/sh\nsleep 10\n")
        FileUtils.chmod(0o755, executable)
        ENV["PATH"] = "#{ffprobe_directory}:#{original_path}"
      end

      after do
        ENV["PATH"] = original_path
        FileUtils.remove_entry(ffprobe_directory)
      end

      it "returns a failed source with the inspection diagnostic" do
        service.call

        expect(source_asset.reload.status).to eq("failed")
        expect(source_asset.inspection_error).to eq("Không thể đọc metadata video. Hãy chọn file MP4/MOV hợp lệ.")
      end
    end
  end
end
