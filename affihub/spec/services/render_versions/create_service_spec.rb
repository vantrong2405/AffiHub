require "rails_helper"

RSpec.describe RenderVersions::CreateService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:source_metadata) { { "duration_seconds" => 6.0, "width" => 32, "height" => 32, "has_audio" => true } }
    let(:source_asset) { create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata) }
    let(:base_edit_config) do
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
    let(:edit_config) { base_edit_config }
    let(:service) { described_class.new(video_project:, source_asset:, edit_config:) }

    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    it "returns a pending version with the config and one render job" do
      service.call

      expect(service).to be_success
      expect(service.render_version.status).to eq("pending")
      expect(service.render_version.version_number).to eq(1)
      expect(service.render_version.edit_config).to eq(edit_config)
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }).to eq([ RenderVersions::RenderJob ])
    end

    context "when the source already has a ready render version" do
      let(:older_render_version) do
        create(:render_version, video_project:, source_asset:, status: "ready", edit_config: base_edit_config,
          metadata: { "duration_seconds" => 4.0 })
      end

      before do
        older_render_version.file.attach(
          io: StringIO.new("older render bytes"),
          filename: "older-render.mp4",
          content_type: "video/mp4"
        )
      end

      it "returns a new version and keeps the older render unchanged" do
        older_blob = older_render_version.file.blob
        service.call

        expect(service.render_version.version_number).to eq(2)
        expect(older_render_version.reload.edit_config).to eq(base_edit_config)
        expect(older_render_version.metadata).to eq({ "duration_seconds" => 4.0 })
        expect(older_render_version.file.blob).to eq(older_blob)
      end
    end

    context "when the timeline has one and two second segments" do
      let(:edit_config) do
        base_edit_config.merge("segments" => [
          { "start_seconds" => 0.0, "end_seconds" => 1.0, "speed" => 1.0, "audio_mode" => "keep", "audio_volume" => 0.8 },
          { "start_seconds" => 2.0, "end_seconds" => 4.0, "speed" => 2.0, "audio_mode" => "mute", "audio_volume" => 0.0 }
        ])
      end

      it "returns the segment order unchanged" do
        service.call

        expect(service.render_version.edit_config["segments"]).to eq(edit_config["segments"])
      end
    end

    context "when a segment is retimed to double speed" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["speed"] = 2.0
        config
      end

      it "returns the configured output speed" do
        service.call

        expect(service.render_version.edit_config.dig("segments", 0, "speed")).to eq(2.0)
      end
    end

    context "when source audio is muted" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["audio_mode"] = "mute"
        config["segments"][0]["audio_volume"] = 0.0
        config
      end

      it "returns the mute choice with the segment" do
        service.call

        expect(service.render_version.edit_config.dig("segments", 0, "audio_mode")).to eq("mute")
      end
    end

    context "when a same-project image is used as the background" do
      let(:image) { create(:project_media_asset, video_project:) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"]["background"] = { "type" => "image", "project_media_asset_id" => image.id }
        config
      end

      it "returns the project-scoped background reference" do
        service.call

        expect(service.render_version.edit_config.dig("canvas", "background", "project_media_asset_id")).to eq(image.id)
      end
    end

    context "when a same-project image is used as a logo" do
      let(:image) { create(:project_media_asset, video_project:) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "logo", "project_media_asset_id" => image.id, "output_start_seconds" => 0.0,
            "output_end_seconds" => 1.0, "x" => 0.7, "y" => 0.05, "width" => 0.2, "height" => 0.1, "opacity" => 0.8 }
        ]
        config
      end

      it "returns the project-scoped logo reference" do
        service.call

        expect(service.render_version.edit_config.dig("overlays", 0, "project_media_asset_id")).to eq(image.id)
      end
    end

    context "when a ready same-project source is used as the video background" do
      let(:background_source) { create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"]["background"] = { "type" => "video", "source_asset_id" => background_source.id }
        config
      end

      it "returns the video background reference" do
        service.call

        expect(service.render_version.edit_config.dig("canvas", "background", "source_asset_id")).to eq(background_source.id)
      end
    end

    context "when crop mode and a solid background color are selected" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"] = { "mode" => "crop", "background" => { "type" => "color", "color" => "#112233" } }
        config
      end

      it "returns the crop mode and color" do
        service.call

        expect(service.render_version.edit_config["canvas"]).to eq(edit_config["canvas"])
      end
    end

    context "when brightness and contrast are adjusted" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["filters"] = { "brightness" => -0.5, "contrast" => 1.8 }
        config
      end

      it "returns the configured filter values" do
        service.call

        expect(service.render_version.edit_config["filters"]).to eq(edit_config["filters"])
      end
    end

    context "when a timed text overlay is configured" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "text", "text" => "Mã giảm giá", "output_start_seconds" => 0.0, "output_end_seconds" => 1.0,
            "x" => 0.1, "y" => 0.8, "width" => 0.8, "height" => 0.1, "opacity" => 1.0 }
        ]
        config
      end

      it "returns the text and its normalized position" do
        service.call

        expect(service.render_version.edit_config["overlays"]).to eq(edit_config["overlays"])
      end
    end

    context "when a timed subtitle is configured" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "subtitle", "text" => "Phụ đề", "output_start_seconds" => 0.2, "output_end_seconds" => 0.9,
            "x" => 0.1, "y" => 0.65, "width" => 0.8, "height" => 0.1, "opacity" => 0.9 }
        ]
        config
      end

      it "returns the subtitle and its output time range" do
        service.call

        expect(service.render_version.edit_config["overlays"]).to eq(edit_config["overlays"])
      end
    end

    context "when the selected source is not ready" do
      let(:source_asset) { create(:source_asset, video_project:, status: "pending", media_metadata: source_metadata) }

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the selected source belongs to another project" do
      let(:source_asset) { create(:source_asset, status: "ready", media_metadata: source_metadata) }

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the background image belongs to another project" do
      let(:image) { create(:project_media_asset) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"]["background"] = { "type" => "image", "project_media_asset_id" => image.id }
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job] }).not_to include(RenderVersions::RenderJob)
      end
    end

    context "when the video background is not ready" do
      let(:background_source) { create(:source_asset, video_project:, status: "pending", media_metadata: source_metadata) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"]["background"] = { "type" => "video", "source_asset_id" => background_source.id }
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the video background belongs to another project" do
      let(:background_source) { create(:source_asset, status: "ready", media_metadata: source_metadata) }
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["canvas"]["background"] = { "type" => "video", "source_asset_id" => background_source.id }
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the schema version is unsupported" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["schema_version"] = 2
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when a segment exceeds source duration" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["end_seconds"] = 7.0
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when a segment has no positive duration" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["end_seconds"] = 0.0
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when segment speed is outside one or two" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["speed"] = 3.0
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the segment audio mode is unsupported" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["audio_mode"] = "stretch"
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when segment audio volume exceeds two" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["segments"][0]["audio_volume"] = 2.1
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when brightness exceeds one" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["filters"]["brightness"] = 1.1
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when contrast exceeds two" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["filters"]["contrast"] = 2.1
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the overlay exceeds output duration" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "text", "text" => "Deal", "output_start_seconds" => 0.0, "output_end_seconds" => 1.1,
            "x" => 0.1, "y" => 0.8, "width" => 0.8, "height" => 0.1, "opacity" => 1.0 }
        ]
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the overlay exceeds canvas bounds" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "text", "text" => "Deal", "output_start_seconds" => 0.0, "output_end_seconds" => 1.0,
            "x" => 0.9, "y" => 0.8, "width" => 0.2, "height" => 0.1, "opacity" => 1.0 }
        ]
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when overlay opacity exceeds one" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["overlays"] = [
          { "type" => "text", "text" => "Deal", "output_start_seconds" => 0.0, "output_end_seconds" => 1.0,
            "x" => 0.1, "y" => 0.8, "width" => 0.8, "height" => 0.1, "opacity" => 1.1 }
        ]
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when a delogo region exceeds source dimensions" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["delogo_regions"] = [ { "x" => 31, "y" => 0, "width" => 2, "height" => 2 } ]
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when edit config contains an unknown key" do
      let(:edit_config) do
        config = base_edit_config.deep_dup
        config["unhandled_option"] = true
        config
      end

      it "returns a validation failure without creating or queueing" do
        service.call

        expect(service).not_to be_success
        expect(RenderVersion.count).to eq(0)
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the user removes a delogo region in the next version" do
      let(:first_config) do
        base_edit_config.merge("delogo_regions" => [ { "x" => 0, "y" => 0, "width" => 8, "height" => 8 } ])
      end
      let(:first_service) { described_class.new(video_project:, source_asset:, edit_config: first_config) }
      let(:previous_version) { first_service.render_version }
      let(:source_file) { File.open(Rails.root.join("spec/fixtures/files/local_source.mp4")) }
      let(:render_file) { File.open(Rails.root.join("spec/fixtures/files/local_source.mp4")) }

      before do
        source_asset.file.attach(io: source_file, filename: "local_source.mp4", content_type: "video/mp4")
        first_service.call
        previous_version.file.attach(io: render_file, filename: "previous-render.mp4", content_type: "video/mp4")
      end

      after do
        source_file.close
        render_file.close
      end

      it "returns a new config while preserving the older version and source files" do
        previous_blob_id = previous_version.file.blob.id
        source_blob_id = source_asset.file.blob.id
        undo_service = described_class.new(video_project:, source_asset:, edit_config: base_edit_config)
        undo_service.call

        expect(undo_service).to be_success
        expect(previous_version.version_number).to eq(1)
        expect(undo_service.render_version.version_number).to eq(2)
        expect(undo_service.render_version).not_to eq(previous_version)
        expect(undo_service.render_version.edit_config["delogo_regions"]).to eq([])
        expect(previous_version.reload.edit_config["delogo_regions"]).to eq(first_config["delogo_regions"])
        expect(previous_version.file.blob.id).to eq(previous_blob_id)
        expect(source_asset.reload.file.blob.id).to eq(source_blob_id)
      end
    end
  end
end
