require "rails_helper"

RSpec.describe Publications::NewService, type: :service do
  describe "#call" do
    it "loads ready and blocked destinations from the selected project's report" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready")
      ready_destination = create(:social_destination)
      blocked_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ ready_destination.id, blocked_destination.id ],
        destination_results: {
          ready_destination.id.to_s => { "status" => "ready" },
          blocked_destination.id.to_s => { "status" => "blocked" }
        }
      )
      service = described_class.new(video_project_id: video_project.id, preflight_report_id: preflight_report.id)

      expect(service.call).to be(true)
      expect(service.video_project).to eq(video_project)
      expect(service.render_version).to eq(render_version)
      expect(service.ready_social_destinations).to eq([ ready_destination ])
      expect(service.blocked_social_destinations).to eq([ blocked_destination ])
    end

    it "returns not found when the selected report belongs to another project" do
      video_project = create(:video_project)
      preflight_report = create(:preflight_report)
      service = described_class.new(video_project_id: video_project.id, preflight_report_id: preflight_report.id)

      expect { service.call }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
