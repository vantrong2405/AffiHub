require "rails_helper"

RSpec.describe VideoProjects::CreateService, type: :service do
  describe "#call" do
    it "returns a persisted video project when the name is present" do
      service = described_class.new(name: "Summer campaign")

      expect { service.call }.to change(VideoProject, :count).by(1)
      expect(service.success?).to be(true)
      expect(service.video_project.name).to eq("Summer campaign")
    end

    it "returns a validation error when the name is blank" do
      service = described_class.new(name: " ")

      expect { service.call }.not_to change(VideoProject, :count)
      expect(service.success?).to be(false)
      expect(service.errors.full_messages).to eq([ "Tên project không được để trống" ])
    end
  end
end
