# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::PollJob, type: :job do
  let(:ai_generation) do
    create(:ai_generation, status: "processing", task_id: "mpt-task-123")
  end

  describe "#perform" do
    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    context "when MPT is still processing the task" do
      let(:task_request) do
        stub_request(:get, "http://mpt.test/api/v1/tasks/mpt-task-123")
          .to_return(
            status: 200,
            body: { status: 200, data: { task_id: "mpt-task-123", state: 4 } }.to_json
          )
      end

      it "enqueues another poll for the saved generation" do
        task_request

        expect(described_class.perform_now(ai_generation.id)).to be(true)

        poll_job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |job|
          job[:job] == described_class
        end
        expect(poll_job[:args]).to eq([ ai_generation.id ])
      end
    end

    context "when MPT reports that the task was interrupted during restart" do
      let(:task_request) do
        stub_request(:get, "http://mpt.test/api/v1/tasks/mpt-task-123")
          .to_return(
            status: 200,
            body: {
              status: 200,
              data: {
                task_id: "mpt-task-123",
                state: -2,
                failed_stage: "mpt_restart"
              }
            }.to_json
          )
      end
      let(:workflow_run) do
        create(
          :workflow_run,
          workflowable: ai_generation,
          operation: "ai_video_generation",
          stage: "mpt_video_submission",
          status: "completed"
        )
      end
      let(:outbound_attempt) do
        create(
          :outbound_attempt,
          workflow_run:,
          stage: AiGenerations::SubmitService::SUBMISSION_STAGE,
          status: "confirmed"
        )
      end

      it "returns false without re-enqueueing the interrupted generation" do
        workflow_run
        outbound_attempt
        task_request

        expect(described_class.perform_now(ai_generation.id)).to be(false)

        expect(ai_generation.reload.status).to eq("outcome_unknown")
        expect(outbound_attempt.reload.status).to eq("outcome_unknown")
        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end

    context "when the generation is already completed" do
      let(:ai_generation) do
        create(:ai_generation, status: "completed", task_id: "mpt-task-123")
      end

      it "does not enqueue another poll" do
        expect(described_class.perform_now(ai_generation.id)).to be(false)

        expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
      end
    end
  end
end
