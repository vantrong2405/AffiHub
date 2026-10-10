require "rails_helper"

RSpec.describe VideoProject, type: :model do
  describe "status" do
    it "returns draft for a newly built project" do
      expect(build(:video_project).status).to eq("draft")
    end

    it "returns processing for a processing project" do
      video_project = build(:video_project, status: "processing")

      expect(video_project.status).to eq("processing")
    end

    it "returns ready for a ready project" do
      video_project = build(:video_project, status: "ready")

      expect(video_project.status).to eq("ready")
    end

    it "returns failed for a failed project" do
      video_project = build(:video_project, status: "failed")

      expect(video_project.status).to eq("failed")
    end
  end

  describe "name" do
    it "returns invalid when the project name is blank" do
      project = build(:video_project, name: " ")

      expect(project).not_to be_valid
    end
  end
end
