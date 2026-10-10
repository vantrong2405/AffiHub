require "rails_helper"

RSpec.describe AiGenerations::ReconcileJob, type: :job do
  after do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  describe "#perform" do
    it "recovers an accepted MPT task without posting another video request" do
      ai_generation = create(:ai_generation, status: "outcome_unknown")
      workflow_run = create(
        :workflow_run,
        workflowable: ai_generation,
        operation: "ai_video_generation",
        stage: "mpt_video_submission",
        status: "reconciliation_required",
        checkpoint: { correlation_id: ai_generation.correlation_id }
      )
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "mpt_video_submission",
        status: "outcome_unknown"
      )
      task_lookup = stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
        .to_return(
          status: 200,
          body: {
            status: 200,
            data: {
              tasks: [
                {
                  task_id: "mpt-task-recovered",
                  request_id: ai_generation.correlation_id,
                  state: 4
                }
              ],
              total: 1,
              page: 1,
              page_size: 2
            }
          }.to_json
        )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now(ai_generation.id)

      expect(ai_generation.reload.task_id).to eq("mpt-task-recovered")
      expect(task_lookup).to have_been_requested.once
      expect(WebMock).not_to have_requested(:post, "http://mpt.test/api/v1/videos")
      expect(ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job.fetch(:job) })
        .to eq([ AiGenerations::PollJob ])
    end

    it "recovers a crashed MPT sender without posting another video request" do
      ai_generation = create(:ai_generation, status: "submitting")
      workflow_run = create(
        :workflow_run,
        workflowable: ai_generation,
        operation: "ai_video_generation",
        stage: "mpt_video_submission",
        status: "reconciliation_required",
        checkpoint: { correlation_id: ai_generation.correlation_id }
      )
      outbound_attempt = create(
        :outbound_attempt,
        workflow_run:,
        stage: "mpt_video_submission",
        status: "submitting",
        sender_stopped_at: nil
      )
      task_lookup = stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
        .to_return(
          status: 200,
          body: {
            status: 200,
            data: {
              tasks: [
                {
                  task_id: "mpt-task-after-restart",
                  request_id: ai_generation.correlation_id,
                  state: 4
                }
              ],
              total: 1,
              page: 1,
              page_size: 2
            }
          }.to_json
        )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.perform_now(ai_generation.id)

      expect(ai_generation.reload.task_id).to eq("mpt-task-after-restart")
      expect(outbound_attempt.reload.status).to eq("confirmed")
      expect(outbound_attempt.sender_stopped_at).not_to eq(nil)
      expect(task_lookup).to have_been_requested.once
      expect(WebMock).not_to have_requested(:post, "http://mpt.test/api/v1/videos")
    end

    it "returns failed reconciliation and leaves a crashed MPT sender unresolved when no task matches" do
      ai_generation = create(:ai_generation, status: "submitting")
      workflow_run = create(
        :workflow_run,
        workflowable: ai_generation,
        operation: "ai_video_generation",
        stage: "mpt_video_submission",
        status: "reconciliation_required",
        checkpoint: { correlation_id: ai_generation.correlation_id }
      )
      outbound_attempt = create(
        :outbound_attempt,
        workflow_run:,
        stage: "mpt_video_submission",
        status: "submitting",
        sender_stopped_at: nil
      )
      task_lookup = stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
        .to_return(
          status: 200,
          body: {
            status: 200,
            data: { tasks: [], total: 0, page: 1, page_size: 2 }
          }.to_json
        )
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      result = described_class.perform_now(ai_generation.id)

      expect(result).to eq(false)
      expect(ai_generation.reload.status).to eq("submitting")
      expect(outbound_attempt.reload.status).to eq("submitting")
      expect(outbound_attempt.sender_stopped_at).to eq(nil)
      expect(workflow_run.reload.status).to eq("reconciliation_required")
      expect(task_lookup).to have_been_requested.once
      expect(WebMock).not_to have_requested(:post, "http://mpt.test/api/v1/videos")
    end
  end
end
