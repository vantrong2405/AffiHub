require "rails_helper"

RSpec.describe VideoProjects::UpdateService, type: :service do
  describe "#call" do
    it "returns the renamed project after a valid update" do
      video_project = create(:video_project, name: "Old name")
      service = described_class.new(video_project_id: video_project.id, name: "New name")

      service.call

      expect(service.video_project.reload.name).to eq("New name")
      expect(service.success?).to be(true)
    end

    it "returns an error and keeps the name when the new name is blank" do
      video_project = create(:video_project, name: "Old name")
      service = described_class.new(video_project_id: video_project.id, name: " ")

      service.call

      expect(service.video_project.reload.name).to eq("Old name")
      expect(service.success?).to be(false)
    end
  end
end
