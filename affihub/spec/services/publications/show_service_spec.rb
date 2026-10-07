require "rails_helper"

RSpec.describe Publications::ShowService, type: :service do
  describe "#call" do
    it "loads the publication, latest report, and workflow from the selected project" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:)
      social_destination = create(:social_destination)
      publication = create(:publication, render_version:, social_destination:)
      preflight_report = create(:preflight_report, render_version:)
      workflow_run = create(:workflow_run, workflowable: publication, operation: "publication_publish", stage: "publish")
      outbound_attempt = create(:outbound_attempt, workflow_run:, stage: "publish")
      service = described_class.new(video_project_id: video_project.id, publication_id: publication.id)

      expect(service.call).to be(true)
      expect(service.video_project).to eq(video_project)
      expect(service.publication).to eq(publication)
      expect(service.latest_preflight_report).to eq(preflight_report)
      expect(service.workflow_run).to eq(workflow_run)
      expect(service.outbound_attempt).to eq(outbound_attempt)
    end

    it "returns not found when the publication belongs to another project" do
      video_project = create(:video_project)
      publication = create(:publication)
      service = described_class.new(video_project_id: video_project.id, publication_id: publication.id)

      expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
