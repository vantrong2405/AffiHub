require "rails_helper"

RSpec.describe SourceAssets::IndexService, type: :service do
  describe "#call" do
    it "returns only source assets that belong to the project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:)
      create(:source_asset)
      service = described_class.new(video_project_id: video_project.id)

      service.call

      expect(service.source_assets).to eq([ source_asset ])
    end
  end
end
