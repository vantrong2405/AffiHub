require "rails_helper"

RSpec.describe SourceAsset, type: :model do
  describe "status" do
    it "returns pending for a newly built source" do
      expect(build(:source_asset).status).to eq("pending")
    end

    it "returns processing for a source under inspection" do
      source_asset = build(:source_asset, status: "processing")

      expect(source_asset.status).to eq("processing")
    end

    it "returns ready for an inspected source" do
      source_asset = build(:source_asset, status: "ready")

      expect(source_asset.status).to eq("ready")
    end

    it "returns failed for a source that could not be inspected" do
      source_asset = build(:source_asset, status: "failed")

      expect(source_asset.status).to eq("failed")
    end
  end

  describe "video project reference" do
    it "returns the project that owns the source" do
      project = build(:video_project)
      source = build(:source_asset, video_project: project)

      expect(source.video_project).to eq(project)
    end
  end
end
