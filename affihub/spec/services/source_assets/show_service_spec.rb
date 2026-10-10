require "rails_helper"

RSpec.describe SourceAssets::ShowService, type: :service do
  describe "#call" do
    it "returns the source asset scoped to its project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:)
      service = described_class.new(video_project_id: video_project.id, source_asset_id: source_asset.id)

      service.call

      expect(service.source_asset).to eq(source_asset)
    end
  end
end
