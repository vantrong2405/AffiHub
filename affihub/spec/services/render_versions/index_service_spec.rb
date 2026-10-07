require "rails_helper"

RSpec.describe RenderVersions::IndexService, type: :service do
  describe "#call" do
    it "returns recent render versions that belong to the selected project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "ready")
      recent_render = create(:render_version, video_project:, source_asset:)
      other_project = create(:video_project)
      other_source = create(:source_asset, video_project: other_project, status: "ready")
      create(:render_version, video_project: other_project, source_asset: other_source)

      service = described_class.new(video_project_id: video_project.id)

      service.call

      expect(service).to be_success
      expect(service.video_project).to eq(video_project)
      expect(service.render_versions).to contain_exactly(recent_render)
    end
  end
end
