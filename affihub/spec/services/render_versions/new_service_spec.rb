require "rails_helper"

RSpec.describe RenderVersions::NewService, type: :service do
  describe "#call" do
    it "returns ready sources and the source selected for the project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "ready")
      create(:source_asset, video_project:, status: "pending")

      service = described_class.new(video_project_id: video_project.id, source_asset_id: source_asset.id)

      service.call

      expect(service).to be_success
      expect(service.source_assets).to contain_exactly(source_asset)
      expect(service.selected_source_asset).to eq(source_asset)
    end

    it "returns a failure when the selected source belongs to another project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, status: "ready")
      service = described_class.new(video_project_id: video_project.id, source_asset_id: source_asset.id)

      service.call

      expect(service).not_to be_success
      expect(service.selected_source_asset).to be_nil
    end
  end
end
