require "rails_helper"

RSpec.describe RenderVersion, type: :model do
  describe "status" do
    it "returns pending for a newly built render version" do
      expect(build(:render_version).status).to eq("pending")
    end

    context "when the render is processing" do
      let(:render_version) { build(:render_version, status: "processing") }

      it "returns processing" do
        expect(render_version.status).to eq("processing")
      end
    end

    context "when the render is ready" do
      let(:render_version) { build(:render_version, status: "ready") }

      it "returns ready" do
        expect(render_version.status).to eq("ready")
      end
    end

    context "when the render has failed" do
      let(:render_version) { build(:render_version, status: "failed") }

      it "returns failed" do
        expect(render_version.status).to eq("failed")
      end
    end
  end

  describe "source reference" do
    it "returns valid when the source is ready and belongs to the same project" do
      project = create(:video_project)
      source = create(:source_asset, video_project: project, status: "ready")
      render_version = build(:render_version, video_project: project, source_asset: source)

      expect(render_version).to be_valid
    end

    it "returns invalid when the source is not ready" do
      project = create(:video_project)
      source = create(:source_asset, video_project: project, status: "pending")
      render_version = build(:render_version, video_project: project, source_asset: source)

      expect(render_version).not_to be_valid
    end

    it "returns invalid when the source belongs to another project" do
      source_project = create(:video_project)
      render_project = create(:video_project)
      source = create(:source_asset, video_project: source_project, status: "ready")
      render_version = build(:render_version, video_project: render_project, source_asset: source)

      expect(render_version).not_to be_valid
    end
  end

  describe "immutable render configuration" do
    let(:video_project) { create(:video_project) }
    let(:source_asset) { create(:source_asset, video_project:, status: "ready") }
    let(:render_version) do
      create(:render_version, video_project:, source_asset:, edit_config: { "schema_version" => 1 })
    end

    context "when the saved edit config changes" do
      it "returns false and keeps the original config" do
        result = render_version.update(edit_config: { "schema_version" => 1, "filters" => {} })

        expect(result).to eq(false)
        expect(render_version.reload.edit_config).to eq({ "schema_version" => 1 })
      end
    end

    context "when the saved source changes" do
      let(:other_source_asset) { create(:source_asset, video_project:, status: "ready") }

      it "returns false and keeps the original source" do
        result = render_version.update(source_asset: other_source_asset)

        expect(result).to eq(false)
        expect(render_version.reload.source_asset).to eq(source_asset)
      end
    end

    context "when the saved version number changes" do
      it "returns false and keeps the original number" do
        result = render_version.update(version_number: 2)

        expect(result).to eq(false)
        expect(render_version.reload.version_number).to eq(1)
      end
    end

    context "when the ready render metadata changes" do
      let(:render_version) do
        create(:render_version, video_project:, source_asset:, status: "ready", metadata: { "width" => 1080 })
      end

      it "returns false and keeps the measured metadata" do
        result = render_version.update(metadata: { "width" => 720 })

        expect(result).to eq(false)
        expect(render_version.reload.metadata).to eq({ "width" => 1080 })
      end
    end
  end
end
