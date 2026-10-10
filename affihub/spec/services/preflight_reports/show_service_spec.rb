# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PreflightReports::ShowService", type: :service do
  let(:service_class) { PreflightReports::ShowService }

  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:source_metadata) { { "duration_seconds" => 2.0 } }
    let(:source_asset) do
      create(:source_asset, video_project:, status: "ready", media_metadata: source_metadata)
    end
    let(:render_version) do
      create(:render_version, video_project:, source_asset:, status: "ready", metadata: source_metadata)
    end
    let(:social_destination) { create(:social_destination) }
    let(:preflight_report) do
      create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results: { social_destination.id.to_s => { "status" => "ready" } }
      )
    end
    let(:service) do
      service_class.new(video_project_id: video_project.id, preflight_report_id: preflight_report.id)
    end

    it "returns paired source and render frames at one-second timecodes for the saved report" do
      frame_strip = [
        { timestamp_seconds: 0.0, source_frame: "source-0", render_frame: "render-0" },
        { timestamp_seconds: 1.0, source_frame: "source-1", render_frame: "render-1" }
      ]
      comparison_service = instance_double(RenderVersions::CompareFramesService, call: true, success?: true, frames: frame_strip)

      expect(RenderVersions::CompareFramesService).to receive(:new).with(
        render_version_id: render_version.id,
        timecodes: [ 0.0, 1.0 ]
      ).and_return(comparison_service)

      expect(service.call).to eq(true)

      expect(service.preflight_report).to eq(preflight_report)
      expect(service.frame_strip).to eq(frame_strip)
      expect(service.render_version).to eq(render_version)
    end

    it "returns the saved report when frame extraction fails" do
      comparison_service = RenderVersions::CompareFramesService.new(
        render_version_id: render_version.id,
        timecodes: [ 0.0 ]
      )
      comparison_service.errors.add(:base, "Không thể tạo khung hình so sánh.")
      allow(RenderVersions::CompareFramesService).to receive(:new).and_return(comparison_service)
      allow(comparison_service).to receive(:call).and_return(false)

      expect(service.call).to eq(true)

      expect(service.preflight_report).to eq(preflight_report)
      expect(service.frame_strip).to eq([])
      expect(service.frame_error).to eq("Không thể tạo khung hình so sánh.")
    end

    it 'returns saved production gates beside the technical destination status' do
      production_gates = [
        {
          "key" => "tiktok_public_visibility",
          "status" => "public_restricted",
          "subject" => "Đăng công khai",
          "reason" => "Content Posting API chưa được audit.",
          "action" => "Chỉ đăng thử với tài khoản private và privacy SELF_ONLY."
        }
      ]
      preflight_report.update!(
        destination_results: {
          social_destination.id.to_s => {
            "status" => "ready",
            "checks" => {},
            "production_gates" => production_gates
          }
        }
      )

      expect(service.call).to eq(true)

      expect(service.destination_entries.first.slice(:status, :production_gates)).to eq(
        status: "ready",
        production_gates:
      )
    end
  end
end
