require "rails_helper"

RSpec.describe VideoProjects::IndexService, type: :service do
  describe "#call" do
    it "returns video projects ordered by name" do
      create(:video_project, name: "Zeta")
      create(:video_project, name: "Alpha")
      service = described_class.new

      service.call

      expect(service.video_projects.map(&:name)).to eq([ "Alpha", "Zeta" ])
    end
  end
end
