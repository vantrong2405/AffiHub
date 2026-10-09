require "rails_helper"

RSpec.describe "DriveExports::UpdateService", type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:render_version) { create(:render_version) }
    let(:drive_export) { create(:drive_export, render_version:, status: "outcome_unknown") }
    let!(:workflow_run) do
      create(
        :workflow_run,
        workflowable: drive_export,
        operation: "drive_export_upload",
        stage: "upload",
        status: "outcome_unknown"
      )
    end
    let(:service_class) { DriveExports::UpdateService }

    context "when the user confirms that the Drive upload occurred" do
      let(:service) do
        service_class.new(
          video_project_id: render_version.video_project_id,
          drive_export_id: drive_export.id,
          decision: "occurred",
          evidence: "Đã kiểm tra file trong thư mục Drive",
          actor_reference: "operator-1",
          provider_reference: "https://drive.google.com/file/d/file-1"
        )
      end

      it "returns a manual confirmation without pretending that the upload was verified by the worker" do
        service.call

        expect(service).to be_success
        expect(drive_export.reload).to have_attributes(
          status: "manual_outcome_confirmed",
          drive_file_id: "file-1"
        )
        expect(workflow_run.reload.workflow_audit_events.sole.details).to eq(
          "decision" => "occurred",
          "evidence" => "Đã kiểm tra file trong thư mục Drive",
          "actor_reference" => "operator-1",
          "provider_reference" => "https://drive.google.com/file/d/file-1"
        )
      end
    end

    context "when the user confirms that the Drive upload did not occur" do
      let(:service) do
        service_class.new(
          video_project_id: render_version.video_project_id,
          drive_export_id: drive_export.id,
          decision: "not_occurred",
          evidence: "Đã kiểm tra và không tìm thấy file",
          actor_reference: "operator-1",
          risk_confirmed: true
        )
      end

      it "returns a recorded decision and enqueues one safe upload retry" do
        expect { service.call }.to have_enqueued_job(DriveExports::UploadJob).with(drive_export.id)

        expect(service).to be_success
        expect(drive_export.reload.status).to eq("queued")
        expect(workflow_run.reload.workflow_audit_events.sole.details).to eq(
          "decision" => "not_occurred",
          "evidence" => "Đã kiểm tra và không tìm thấy file",
          "actor_reference" => "operator-1",
          "risk_confirmed" => true
        )
      end
    end

    context "when the user leaves the outcome unresolved" do
      let(:service) do
        service_class.new(
          video_project_id: render_version.video_project_id,
          drive_export_id: drive_export.id,
          decision: "unknown",
          evidence: "Google chưa trả kết quả đối soát",
          actor_reference: "operator-1"
        )
      end

      it "returns an unresolved export and does not enqueue a retry" do
        service.call

        expect(service).to be_success
        expect(drive_export.reload.status).to eq("outcome_unknown")
        expect(workflow_run.reload.workflow_audit_events.sole.details).to eq(
          "decision" => "unknown",
          "evidence" => "Google chưa trả kết quả đối soát",
          "actor_reference" => "operator-1",
          "risk_confirmed" => false
        )
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
      end
    end

    context "when the user confirms no upload without acknowledging retry risk" do
      let(:service) do
        service_class.new(
          video_project_id: render_version.video_project_id,
          drive_export_id: drive_export.id,
          decision: "not_occurred",
          evidence: "Không tìm thấy file",
          actor_reference: "operator-1"
        )
      end

      it "rejects the retry and keeps the export unresolved" do
        service.call

        expect(service).not_to be_success
        expect(drive_export.reload.status).to eq("outcome_unknown")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to eq([])
      end
    end

    context "when the browser submits an acknowledged retry checkbox" do
      let(:service) do
        service_class.new(
          video_project_id: render_version.video_project_id,
          drive_export_id: drive_export.id,
          decision: "not_occurred",
          evidence: "Đã kiểm tra và không tìm thấy file",
          actor_reference: "operator-1",
          risk_confirmed: "1"
        )
      end

      it "returns a queued retry after the user checks the risk confirmation" do
        expect { service.call }.to have_enqueued_job(DriveExports::UploadJob).with(drive_export.id)

        expect(service).to be_success
        expect(drive_export.reload.status).to eq("queued")
      end
    end
  end
end
