require "rails_helper"

RSpec.describe Publications::ConfirmService, type: :service do
  describe "#call" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    let(:render_version) { create(:render_version) }
    let(:social_destination) { create(:social_destination) }
    let(:publication) do
      create(:publication, render_version:, social_destination:, status: "draft")
    end
    let(:destination_results) do
      { social_destination.id.to_s => { "status" => "ready" } }
    end
    let(:preflight_report) do
      create(
        :preflight_report,
        render_version:,
        checked_destination_ids: [ social_destination.id ],
        destination_results:
      )
    end
    let(:service) do
      described_class.new(
        publication_id: publication.id,
        preflight_report_id: preflight_report.id
      )
    end

    it "approves only the reviewed Publication and queues its workflow" do
      expect { service.call }.to have_enqueued_job(Publications::PublishJob)

      expect(service).to be_success
      expect(publication.reload.status).to eq("approved")
      expect(WorkflowRun.find_by!(workflowable: publication)).to have_attributes(status: "queued")
    end

    context "when the destination is now blocked by preflight" do
      let(:destination_results) do
        { social_destination.id.to_s => { "status" => "blocked" } }
      end

      it "keeps the draft and does not queue a publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the report does not include the Publication destination" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version:,
          checked_destination_ids: [],
          destination_results: {}
        )
      end

      it "returns failure without starting the publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
      end
    end

    context "when the report belongs to another render version" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version: create(:render_version),
          checked_destination_ids: [ social_destination.id ],
          destination_results:
        )
      end

      it "returns failure without starting the publish workflow" do
        expect { service.call }.not_to change(WorkflowRun, :count)

        expect(service).not_to be_success
        expect(publication.reload.status).to eq("draft")
      end
    end
  end
end
