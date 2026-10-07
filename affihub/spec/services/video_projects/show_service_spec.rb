require "rails_helper"

RSpec.describe VideoProjects::ShowService, type: :service do
  describe "#call" do
    it "returns source assets that belong to the project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:)
      create(:source_asset)
      service = described_class.new(video_project_id: video_project.id)

      service.call

      expect(service.source_assets).to eq([ source_asset ])
    end

    it "returns render versions that belong to the project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      create(:render_version)
      service = described_class.new(video_project_id: video_project.id)

      service.call

      expect(service.render_versions).to eq([ render_version ])
    end
  end
end
