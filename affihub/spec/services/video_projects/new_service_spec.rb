require "rails_helper"

RSpec.describe VideoProjects::NewService, type: :service do
  describe "#call" do
    it "returns an unsaved video project" do
      service = described_class.new

      service.call

      expect(service.video_project).to be_a_new(VideoProject)
    end
  end
end
