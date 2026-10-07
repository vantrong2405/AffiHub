require "rails_helper"
require "tmpdir"

RSpec.describe RenderVersions::RenderService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:source_metadata) { { "duration_seconds" => 2.0, "width" => 32, "height" => 32, "has_audio" => true } }
    let(:source_asset) { create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata) }
    let(:source_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:edit_config) do
      {
        "schema_version" => 1,
        "segments" => [
          { "start_seconds" => 0.0, "end_seconds" => 2.0, "speed" => 2.0, "audio_mode" => "keep", "audio_volume" => 1.0 }
        ],
        "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
        "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
        "overlays" => [],
        "delogo_regions" => []
      }
    end
    let(:render_version) { create(:render_version, video_project:, source_asset:, status: "pending", edit_config:) }
    let(:service) { described_class.new(render_version_id: render_version.id) }

    before do
      source_asset.file.attach(io: source_file, filename: "edit_source.mp4", content_type: "video/mp4")
    end

    after { source_file.close }

    context "when FFmpeg is missing" do
      let(:ffmpeg_directory) { Dir.mktmpdir("affihub-no-ffmpeg") }
      let(:original_path) { ENV.fetch("PATH") }
      let(:older_version) { create(:render_version, video_project:, source_asset:, status: "ready") }
      let(:older_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
      let(:render_version) { create(:render_version, video_project:, source_asset:, status: "pending", version_number: 2, edit_config:) }

      before do
        original_path
        ENV["PATH"] = ffmpeg_directory
        older_version.file.attach(io: older_file, filename: "older-render.mp4", content_type: "video/mp4")
        service.call
      end

      after do
        ENV["PATH"] = original_path
        FileUtils.remove_entry(ffmpeg_directory)
        older_file.close
      end

      it "returns a failed version and keeps the older files" do
        older_blob_id = older_version.file.blob.id

        expect(render_version.reload.status).to eq("failed")
        expect(render_version.render_error).to eq("Không tìm thấy FFmpeg trên worker.")
        expect(older_version.reload.file.blob.id).to eq(older_blob_id)
        expect(source_asset.reload.status).to eq("ready")
        expect(source_asset.file).to be_attached
      end
    end

    context "when FFmpeg renders a two second source segment at double speed" do
      before { service.call }

      it "returns measured MP4 duration and H.264, AAC, portrait metadata" do
        metadata = render_version.reload.metadata

        expect(render_version.status).to eq("ready")
        expect(render_version.file).to be_attached
        expect(render_version.render_error).to be_nil
        expect(metadata["duration_seconds"]).to be_within(0.15).of(1.0)
        expect(metadata.slice("video_codec", "audio_codec", "width", "height", "frame_rate", "has_audio")).to eq(
          { "video_codec" => "h264", "audio_codec" => "aac", "width" => 1080, "height" => 1920, "frame_rate" => "30/1", "has_audio" => true }
        )
        expect(metadata["file_size_bytes"]).to eq(render_version.file.byte_size)
      end
    end

    context "when rendering a later version of the same source" do
      let(:older_render_version) do
        create(:render_version, video_project:, source_asset:, version_number: 1, status: "ready", edit_config:)
      end
      let(:render_version) do
        create(:render_version, video_project:, source_asset:, version_number: 2, status: "pending", edit_config:)
      end

      before do
        older_render_version.file.attach(
          io: StringIO.new("older render bytes"),
          filename: "older-render.mp4",
          content_type: "video/mp4"
        )
      end

      it "returns a separate file and keeps the older render file" do
        older_blob = older_render_version.file.blob
        service.call

        expect(render_version.reload.file.blob).not_to eq(older_blob)
        expect(older_render_version.reload.file.blob).to eq(older_blob)
      end
    end

    context "when the source segment audio is muted" do
      let(:edit_config) do
        config = super().deep_dup
        config["segments"][0]["end_seconds"] = 1.0
        config["segments"][0]["speed"] = 1.0
        config["segments"][0]["audio_mode"] = "mute"
        config["segments"][0]["audio_volume"] = 0.0
        config
      end
      let(:source_metadata) { { "duration_seconds" => 2.0, "width" => 32, "height" => 32, "has_audio" => true } }

      before { service.call }

      it "returns a ready version with no audio stream" do
        expect(render_version.reload.status).to eq("ready")
        expect(render_version.metadata["has_audio"]).to eq(false)
        expect(render_version.metadata["audio_codec"]).to be_nil
      end
    end
  end
end
