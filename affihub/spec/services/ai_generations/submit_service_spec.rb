# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiGenerations::SubmitService, type: :service do
  let(:generation_inputs) do
    {
      video_subject: "Summer skincare",
      video_script: "A short summer skincare story.",
      language: "vi",
      model_id: "seedance-lite-t2v",
      resolution: "480p",
      scenes: [ { prompt: "A sunny bathroom", duration: 6, approved: true } ]
    }
  end
  let(:estimate_snapshot) { generation_inputs }
  let(:estimate) do
    {
      total_amount: "0.50",
      currency: "USD",
      required_costs_known: true,
      input_snapshot: estimate_snapshot
    }
  end
  let(:budget) { "1.00" }
  let(:confirmed) { true }
  let(:video_project) { create(:video_project) }
  let(:service) do
    described_class.new(
      video_project:,
      inputs: generation_inputs,
      estimate: estimate,
      budget: budget,
      confirmed: confirmed
    )
  end
  let(:expected_video_request) do
    {
      video_subject: "Summer skincare",
      video_script: "A short summer skincare story.",
      video_terms: [ "A sunny bathroom" ],
      video_aspect: "9:16",
      video_clip_duration: 6,
      video_count: 1,
      video_source: "muapi",
      video_language: "vi",
      voice_name: "chatterbox:Mai Anh",
      subtitle_enabled: true,
      match_materials_to_script: true
    }
  end
  let(:video_request) do
    stub_request(:post, %r{/api/v1/videos\z})
      .with(body: expected_video_request.deep_stringify_keys)
      .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json)
  end

  describe "#call" do
    before { video_request }
    subject(:call_result) { service.call }

    context "when cost confirmation is missing" do
      let(:confirmed) { false }

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the estimate exceeds the budget" do
      let(:budget) { "0.49" }

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the budget is missing" do
      let(:budget) { nil }

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when a required cost is unknown" do
      let(:estimate) { super().merge(required_costs_known: false) }

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when inputs change after the estimate" do
      let(:generation_inputs) do
        super().merge(scenes: [ { prompt: "A bright bathroom", duration: 6, approved: true } ])
      end
      let(:estimate_snapshot) do
        super().merge(scenes: [ { prompt: "A sunny bathroom", duration: 6, approved: true } ])
      end

      it "returns invalid without submitting the stale estimate" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when any scene prompt is not approved" do
      let(:generation_inputs) do
        super().merge(scenes: [ { prompt: "A sunny bathroom", duration: 6, approved: false } ])
      end

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when scene durations differ" do
      let(:generation_inputs) do
        super().merge(scenes: [
          { prompt: "A sunny bathroom", duration: 6, approved: true },
          { prompt: "A skincare bottle", duration: 5, approved: true }
        ])
      end

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when scene duration is outside the configured range" do
      let(:generation_inputs) do
        super().merge(scenes: [ { prompt: "A sunny bathroom", duration: 13, approved: true } ])
      end

      it "returns invalid without submitting the video job" do
        call_result

        expect(service.success?).to be(false)
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the estimate is confirmed and every scene is approved" do
      it "returns the accepted MPT task ID" do
        call_result

        expect(service.task_id).to eq("mpt-task-123")
      end

      it "sends the expected video request to MPT" do
        call_result

        expect(service.video_request).to eq(expected_video_request)
      end

      it "submits one video request to MPT" do
        call_result

        expect(video_request).to have_been_requested.once
      end
    end

    context "when MPT already accepted the saved generation" do
      let(:ai_generation) do
        create(:ai_generation, video_project:, status: "processing", task_id: "mpt-task-existing")
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
      let!(:outbound_attempt) do
        create(
          :outbound_attempt,
          workflow_run:,
          stage: "mpt_video_submission",
          status: "confirmed"
        )
      end
      let(:service) { described_class.new(ai_generation_id: ai_generation.id) }

      it "returns success for the saved task" do
        expect(call_result).to be(true)
      end

      it "returns the existing MPT task ID" do
        call_result

        expect(service.task_id).to eq("mpt-task-existing")
      end

      it "does not submit another video request" do
        call_result

        expect(video_request).not_to have_been_requested
      end

      it "does not request the MPT task list" do
        call_result

        expect(WebMock).not_to have_requested(:get, %r{/api/v1/tasks})
      end
    end

    context "when MPT accepts the request without returning a task ID" do
      let(:video_request) do
        stub_request(:post, %r{/api/v1/videos\z})
          .with(body: expected_video_request.deep_stringify_keys)
          .to_return(status: 200, body: { status: 200, data: { state: 4 } }.to_json)
      end
      let(:task_list_request) do
        stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
          .to_return do
            ai_generation = AiGeneration.order(:id).last
            task_page = {
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

            { status: 200, body: { status: 200, data: task_page }.to_json }
          end
      end

      before { task_list_request }

      it "returns the task ID found during reconciliation" do
        call_result

        expect(service.task_id).to eq("mpt-task-recovered")
      end

      it "checks the MPT task list once" do
        call_result

        expect(task_list_request).to have_been_requested.once
      end

      it "does not send another video request during reconciliation" do
        call_result

        expect(video_request).to have_been_requested.once
      end
    end

    context "when the submission must be stored before MPT receives it" do
      let(:service) do
        described_class.new(
          video_project:,
          inputs: generation_inputs,
          estimate:,
          budget:,
          confirmed:
        )
      end
      let(:submission_observations) { {} }
      let(:video_request) do
        observations = submission_observations

        stub_request(:post, %r{/api/v1/videos\z})
          .with(body: expected_video_request.deep_stringify_keys)
          .to_return do
            ai_generation = AiGeneration.order(:id).last
            workflow_run = ai_generation.workflow_run
            outbound_attempt = workflow_run.outbound_attempts.sole

            observations[:correlation_id] = ai_generation.correlation_id
            observations[:input_snapshot] = ai_generation.input_snapshot
            observations[:estimate_snapshot] = ai_generation.estimate_snapshot
            observations[:consent_snapshot] = ai_generation.consent_snapshot
            observations[:attempt_status] = outbound_attempt.status

            { status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json }
          end
      end

      it "persists the approved input snapshot before the MPT request" do
        call_result

        expect(submission_observations[:input_snapshot]).to eq(generation_inputs.deep_stringify_keys)
      end

      it "persists the approved estimate before the MPT request" do
        call_result

        expect(submission_observations[:estimate_snapshot]).to eq(estimate.deep_stringify_keys)
      end

      it "persists the user's cost consent before the MPT request" do
        call_result

        expect(submission_observations[:consent_snapshot]).to include(
          "confirmed" => true,
          "amount" => "0.50",
          "currency" => "USD"
        )
      end

      it "persists the submitting attempt before the MPT request" do
        call_result

        expect(submission_observations[:attempt_status]).to eq("submitting")
      end

      it "sends the generation's saved correlation ID in the MPT header" do
        call_result

        expect(
          a_request(:post, "http://mpt.test/api/v1/videos")
            .with(headers: { "x-task-id" => submission_observations[:correlation_id] })
        ).to have_been_made.once
      end

      it "stores the accepted MPT task ID on the generation" do
        call_result

        expect(service.ai_generation.reload.task_id).to eq("mpt-task-123")
      end
    end

    context "when MPT accepts a task but the submit response is lost" do
      let(:service) do
        described_class.new(
          video_project:,
          inputs: generation_inputs,
          estimate:,
          budget:,
          confirmed:
        )
      end
      let(:video_request) do
        stub_request(:post, %r{/api/v1/videos\z})
          .with(body: expected_video_request.deep_stringify_keys)
          .to_timeout
      end
      let(:task_list_request) do
        stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
          .to_return do
            ai_generation = AiGeneration.order(:id).last
            task_page = {
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

            { status: 200, body: { status: 200, data: task_page }.to_json }
          end
      end

      before { task_list_request }

      it "returns success when the task is found by request ID" do
        call_result

        expect(service).to be_success
      end

      it "stores the recovered MPT task ID" do
        call_result

        expect(service.ai_generation.reload.task_id).to eq("mpt-task-recovered")
      end

      it "does not submit another video request during recovery" do
        call_result

        expect(video_request).to have_been_requested.once
      end

      it "checks the task list once during recovery" do
        call_result

        expect(task_list_request).to have_been_requested.once
      end

      context "when no task matches the saved correlation ID" do
        let(:task_list_request) do
          stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
            .to_return(
              status: 200,
              body: {
                status: 200,
                data: { tasks: [], total: 0, page: 1, page_size: 2 }
              }.to_json
            )
        end

        let(:recovery_service) { described_class.new(ai_generation_id: service.ai_generation.id) }

        before do
          call_result
          recovery_service.call
        end

        it "keeps the generation outcome unknown after restart" do
          expect(service.ai_generation.reload.status).to eq("outcome_unknown")
        end

        it "keeps the outbound attempt outcome unknown after restart" do
          expect(service.ai_generation.workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
        end

        it "blocks a second video submission after restart" do
          expect(video_request).to have_been_requested.once
        end
      end

      context "when the task list cannot be reached" do
        let(:task_list_request) do
          stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2").to_timeout
        end

        let(:recovery_service) { described_class.new(ai_generation_id: service.ai_generation.id) }

        before do
          call_result
          recovery_service.call
        end

        it "keeps the generation outcome unknown when the task list is unavailable" do
          expect(service.ai_generation.reload.status).to eq("outcome_unknown")
        end

        it "keeps the outbound attempt outcome unknown when the task list is unavailable" do
          expect(service.ai_generation.workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
        end

        it "does not submit the video twice when the task list is unavailable" do
          expect(video_request).to have_been_requested.once
        end
      end

      context "when the matching task is on a later page" do
        let(:task_list_request) do
          stub_request(:get, "http://mpt.test/api/v1/tasks?page=1&page_size=2")
            .to_return(
              status: 200,
              body: {
                status: 200,
                data: {
                  tasks: [
                    { task_id: "other-task-1", request_id: "other-request-1", state: 4 },
                    { task_id: "other-task-2", request_id: "other-request-2", state: 4 }
                  ],
                  total: 3,
                  page: 1,
                  page_size: 2
                }
              }.to_json
            )
        end
        let(:task_list_page_two_request) do
          stub_request(:get, "http://mpt.test/api/v1/tasks?page=2&page_size=2")
            .to_return do
              ai_generation = AiGeneration.order(:id).last
              task_page = {
                tasks: [
                  {
                    task_id: "mpt-task-recovered",
                    request_id: ai_generation.correlation_id,
                    state: 4
                  }
                ],
                total: 3,
                page: 2,
                page_size: 2
              }

              { status: 200, body: { status: 200, data: task_page }.to_json }
            end
        end

        before { task_list_page_two_request }

        it "stores the task found on the later page" do
          call_result

          expect(service.ai_generation.reload.task_id).to eq("mpt-task-recovered")
        end

        it "requests the later task-list page once" do
          call_result

          expect(task_list_page_two_request).to have_been_requested.once
        end

        it "does not resubmit the video while checking later pages" do
          call_result

          expect(video_request).to have_been_requested.once
        end
      end
    end
  end
end
