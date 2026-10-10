require "rails_helper"

RSpec.describe VideoProjects::DestroyService, type: :service do
  describe "#call" do
    it "returns success after deleting an empty project" do
      video_project = create(:video_project)
      service = described_class.new(video_project_id: video_project.id)

      expect { service.call }.to change(VideoProject, :count).by(-1)
      expect(service.success?).to be(true)
    end

    it "returns an error and keeps a project that has source assets" do
      video_project = create(:video_project)
      create(:source_asset, video_project:)
      service = described_class.new(video_project_id: video_project.id)

      expect { service.call }.not_to change(VideoProject, :count)
      expect(service.success?).to be(false)
    end
  end
end
