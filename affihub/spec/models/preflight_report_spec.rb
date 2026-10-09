require "rails_helper"

RSpec.describe PreflightReport, type: :model do
  describe "#ready_for?" do
    it "returns true when the report marks its selected destination ready for the exact render" do
      render_version = create(:render_version)
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )

      expect(preflight_report.ready_for?(render_version:, social_destination:)).to eq(true)
    end

    it "returns false when the report belongs to another render version" do
      preflight_report = create(:preflight_report)
      other_render_version = create(:render_version)
      social_destination = create(:social_destination)

      expect(preflight_report.ready_for?(render_version: other_render_version, social_destination:)).to eq(false)
    end

    it "returns false when the destination was not in the checked scope" do
      render_version = create(:render_version)
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )

      expect(preflight_report.ready_for?(render_version:, social_destination:)).to eq(false)
    end

    it "returns false when the selected destination did not pass preflight" do
      render_version = create(:render_version)
      social_destination = create(:social_destination)
      preflight_report = create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "blocked" } }
      )

      expect(preflight_report.ready_for?(render_version:, social_destination:)).to eq(false)
    end
  end
end
