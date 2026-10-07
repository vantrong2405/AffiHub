require "rails_helper"

RSpec.describe VideoProjects::EditService, type: :service do
  describe "#call" do
    it "returns the project for editing" do
      video_project = create(:video_project)
      service = described_class.new(video_project_id: video_project.id)

      service.call

      expect(service.video_project).to eq(video_project)
    end
  end
end
