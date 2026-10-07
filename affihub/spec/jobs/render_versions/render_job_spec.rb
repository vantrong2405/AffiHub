require "rails_helper"
require "tmpdir"

RSpec.describe RenderVersions::RenderJob, type: :job do
  describe "#perform" do
    let(:video_project) { create(:video_project) }
    let(:source_metadata) { { "duration_seconds" => 2.0, "width" => 32, "height" => 32, "has_audio" => true } }
    let(:source_asset) { create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata) }
    let(:source_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:render_version) { create(:render_version, video_project:, source_asset:, version_number: 2, edit_config: edit_config) }
    let(:edit_config) do
      {
        "schema_version" => 1,
        "segments" => [
          { "start_seconds" => 0.0, "end_seconds" => 1.0, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 1.0 }
        ],
        "canvas" => { "mode" => "fit", "background" => { "type" => "blur" } },
        "filters" => { "brightness" => 0.0, "contrast" => 1.0 },
        "overlays" => [],
        "delogo_regions" => []
      }
    end
    let(:older_version) { create(:render_version, video_project:, source_asset:, status: "ready") }
    let(:older_file) { File.open(Rails.root.join("spec/fixtures/files/edit_source.mp4")) }
    let(:older_blob_id) { older_version.file.blob.id }
    let(:ffmpeg_directory) { Dir.mktmpdir("affihub-slow-ffmpeg") }
    let(:ffmpeg_path) { File.join(ffmpeg_directory, "ffmpeg") }
    let(:original_path) { ENV.fetch("PATH") }

    before do
      original_path
      source_asset.file.attach(io: source_file, filename: "edit_source.mp4", content_type: "video/mp4")
      older_version.file.attach(io: older_file, filename: "older-render.mp4", content_type: "video/mp4")
      File.write(ffmpeg_path, "#!/bin/sh\n/bin/sleep 30\n")
      FileUtils.chmod(0o755, ffmpeg_path)
      ENV["PATH"] = "#{ffmpeg_directory}:#{original_path}"
      described_class.perform_now(render_version.id)
    end

    after do
      ENV["PATH"] = original_path
      FileUtils.remove_entry(ffmpeg_directory)
      source_file.close
      older_file.close
    end

    it "returns a failed version and retains its source and older render" do
      expect(render_version.reload.status).to eq("failed")
      expect(render_version.render_error).to eq("Render vượt quá giới hạn thời gian cho phép.")
      expect(older_version.reload.file.blob.id).to eq(older_blob_id)
      expect(source_asset.reload.status).to eq("ready")
      expect(source_asset.file).to be_attached
    end
  end
end
