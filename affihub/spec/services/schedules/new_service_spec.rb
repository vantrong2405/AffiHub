require "rails_helper"

RSpec.describe Schedules::NewService, type: :service do
  describe "#call" do
    it "returns the machine timezone and destinations ready in the selected report" do
      video_project = create(:video_project)
      render_version = create(:render_version, video_project:, status: "ready")
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TZ").and_return("Asia/Ho_Chi_Minh")
      service = described_class.new(video_project_id: video_project.id, preflight_report_id: preflight_report.id)

      expect(service.call).to eq(true)

      expect(service.video_project).to eq(video_project)
      expect(service.preflight_report).to eq(preflight_report)
      expect(service.ready_social_destinations).to eq([ social_destination ])
      expect(service.time_zone).to eq("Asia/Ho_Chi_Minh")
    end

    context "when a TikTok destination has no current Publication consent" do
      it "returns that destination as requiring consent review" do
        video_project = create(:video_project)
        render_version = create(:render_version, video_project:, status: "ready")
        social_connection = create(:social_connection, provider: "tiktok", external_user_id: "creator-1")
        social_destination = create(
          :social_destination,
          social_connection:,
          provider: "tiktok",
          external_id: "creator-1"
        )
        preflight_report = create(
          :preflight_report,
          render_version:,
          checked_destination_ids: [ social_destination.id ],
          destination_results: { social_destination.id.to_s => { "status" => "ready" } }
        )
        service = described_class.new(video_project_id: video_project.id, preflight_report_id: preflight_report.id)

        expect(service.call).to eq(true)

        expect(service.consent_required_destination_ids).to eq([ social_destination.id ])
      end
    end
  end
end
