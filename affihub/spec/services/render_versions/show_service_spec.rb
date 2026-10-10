require "rails_helper"

RSpec.describe RenderVersions::ShowService, type: :service do
  describe "#call" do
    it "returns the render version and source for the selected project" do
      video_project = create(:video_project)
      source_asset = create(:source_asset, video_project:, status: "ready")
      render_version = create(:render_version, video_project:, source_asset:)
      service = described_class.new(video_project_id: video_project.id, render_version_id: render_version.id)

      service.call

      expect(service).to be_success
      expect(service.video_project).to eq(video_project)
      expect(service.render_version).to eq(render_version)
      expect(service.source_asset).to eq(source_asset)
    end

    it "raises not found when the render version belongs to another project" do
      video_project = create(:video_project)
      render_version = create(:render_version)
      service = described_class.new(video_project_id: video_project.id, render_version_id: render_version.id)

      expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
