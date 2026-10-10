require "rails_helper"

RSpec.describe Publications::IndexService, type: :service do
  describe "#call" do
    it "loads only publications for the selected project in recent order" do
      video_project = create(:video_project)
      other_publication = create(:publication)
      older_publication = create(:publication, render_version: create(:render_version, video_project:))
      newer_publication = create(:publication, render_version: create(:render_version, video_project:))
      service = described_class.new(video_project_id: video_project.id)

      expect(service.call).to be(true)
      expect(service.publications).to eq([ newer_publication, older_publication ])
      expect(service.publications).not_to include(other_publication)
    end
  end
end
