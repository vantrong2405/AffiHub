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
  let(:tts_fallback_quote) do
    {
      amount: "0.01",
      currency: "USD",
      provider: "Azure Speech",
      source: "Azure Speech pricing estimate",
      estimated_at: 1.minute.ago.iso8601,
      input_snapshot: {
        narration: generation_inputs.fetch(:video_script),
        voice: "vi-VN-HoaiMyNeural"
      }
    }
  end
  let(:estimate) do
    {
      total_amount: "0.50",
      currency: "USD",
      required_costs_known: true,
      input_snapshot: estimate_snapshot,
      cost_breakdown: {
        tts_fallback: tts_fallback_quote
      }
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
      tts_fallback_voice: "vi-VN-HoaiMyNeural",
      subtitle_enabled: true,
      match_materials_to_script: true
    }
  end
  let(:video_request) do
    stub_request(:post, %r{/api/v1/videos\z})
      .to_return do
        ai_generation = AiGeneration.order(:id).last
        ai_generation_scene = ai_generation&.ai_generation_scenes&.find_by(scene_index: 0)
        if ai_generation_scene
          submission_scene_snapshot[:attributes] = ai_generation_scene.attributes.slice(
            "scene_index",
            "status",
            "narration_snapshot",
            "voice_name"
          )
          submission_scene_snapshot[:estimate_snapshot] = ai_generation_scene.estimate_snapshot
          submission_scene_snapshot[:consent_snapshot] = ai_generation_scene.consent_snapshot
        end

        { status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json }
      end
  end
  let(:submission_scene_snapshot) { {} }

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

    context "when the TTS fallback quote is missing" do
      let(:estimate) { super().except(:cost_breakdown) }

      it "does not submit a video job without an Azure quote" do
        call_result

        expect(service).not_to be_success
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the TTS fallback quote is for different narration" do
      let(:tts_fallback_quote) do
        super().merge(
          input_snapshot: {
            narration: "Different narration.",
            voice: "vi-VN-HoaiMyNeural"
          }
        )
      end

      it "does not submit a video job with a mismatched Azure quote" do
        call_result

        expect(service).not_to be_success
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the TTS fallback quote is for a different Azure voice" do
      let(:tts_fallback_quote) do
        super().merge(
          input_snapshot: {
            narration: generation_inputs.fetch(:video_script),
            voice: "vi-VN-NamMinhNeural"
          }
        )
      end

      it "does not submit a video job with a mismatched Azure voice quote" do
        call_result

        expect(service).not_to be_success
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the TTS fallback quote has expired" do
      let(:tts_fallback_quote) do
        super().merge(estimated_at: 2.hours.ago.iso8601)
      end

      it "does not submit a video job with an expired Azure quote" do
        call_result

        expect(service).not_to be_success
        expect(video_request).not_to have_been_requested
      end
    end

    context "when the TTS fallback quote uses a different currency" do
      let(:tts_fallback_quote) { super().merge(currency: "EUR") }

      it "does not submit a video job with a currency mismatch" do
        call_result

        expect(service).not_to be_success
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
      it "submits the approved request and stores its TTS fallback details" do
        call_result

        expect(service.task_id).to eq("mpt-task-123")
        expect(service.video_request).to eq(expected_video_request)
        expect(submission_scene_snapshot.fetch(:attributes).slice("scene_index", "status")).to eq(
          "scene_index" => 0,
          "status" => "processing"
        )
        expect(submission_scene_snapshot.fetch(:attributes).fetch("narration_snapshot")).to eq(
          generation_inputs.fetch(:video_script)
        )
        expect(submission_scene_snapshot.fetch(:attributes).fetch("voice_name")).to eq(
          "vi-VN-HoaiMyNeural"
        )
        expect(submission_scene_snapshot.fetch(:estimate_snapshot)).to eq(
          estimate.fetch(:cost_breakdown).fetch(:tts_fallback).deep_stringify_keys
        )
        expect(submission_scene_snapshot.fetch(:consent_snapshot)).to include(
          "confirmed" => true,
          "estimate" => estimate.fetch(:cost_breakdown).fetch(:tts_fallback).deep_stringify_keys
        )
        expect(video_request).to have_been_requested.once
        poll_job = ActiveJob::Base.queue_adapter.enqueued_jobs.find do |job|
          job[:job] == AiGenerations::PollJob
        end
        expect(poll_job[:args]).to eq([ service.ai_generation.id ])
      end
    end

    context "when submitting a saved and approved generation" do
      let(:draft_generation) do
        create(
          :ai_generation,
          video_project: video_project,
          status: :prompts_ready,
          input_snapshot: generation_inputs,
          estimate_snapshot: estimate
        )
      end
      let(:service) do
        described_class.new(
          video_project: video_project,
          draft_generation_id: draft_generation.id,
          budget: budget,
          confirmed: confirmed
        )
      end

      it "submits the saved snapshot without creating another generation" do
        draft_generation
        expect { call_result }.not_to change(AiGeneration, :count)

        expect(service.ai_generation).to eq(draft_generation)
        expect(service.ai_generation.reload.input_snapshot).to eq(generation_inputs.deep_stringify_keys)
        expect(service.ai_generation.estimate_snapshot).to eq(estimate.deep_stringify_keys)
        expect(service.ai_generation.consent_snapshot).to include(
          "confirmed" => true,
          "amount" => "0.50",
          "budget" => "1.00",
          "currency" => "USD"
        )
        expect(video_request).to have_been_requested.once
      end
    end

    context "when retrying a generation confirmed as not submitted" do
      let(:draft_generation) do
        create(
          :ai_generation,
          video_project: video_project,
          status: :outcome_unknown,
          input_snapshot: generation_inputs,
          estimate_snapshot: estimate
        )
      end
      let(:workflow_run) do
        create(
          :workflow_run,
          workflowable: draft_generation,
          operation: "ai_video_generation",
          stage: "mpt_video_submission",
          status: "queued"
        )
      end
      let(:previous_attempt) do
        create(
          :outbound_attempt,
          workflow_run: workflow_run,
          stage: "mpt_video_submission",
          status: "manual_outcome_not_occurred",
          sender_stopped_at: 2.minutes.ago,
          request_timeout_at: 1.minute.ago
        )
      end
      let(:service) do
        described_class.new(
          video_project: video_project,
          draft_generation_id: draft_generation.id,
          budget: budget,
          confirmed: confirmed
        )
      end

      it "reuses the saved generation and starts the next safe attempt" do
        previous_attempt

        expect { call_result }.not_to change(AiGeneration, :count)

        expect(service).to be_success
        expect(service.ai_generation).to eq(draft_generation)
        expect(workflow_run.reload.outbound_attempts.order(:attempt_number).pluck(:attempt_number, :status)).to eq(
          [ [ 1, "manual_outcome_not_occurred" ], [ 2, "confirmed" ] ]
        )
        expect(draft_generation.ai_generation_scenes.count).to eq(1)
        expect(video_request).to have_been_requested.once
      end
    end

    context "when MPT rejects the video submission" do
      let(:video_request) do
        stub_request(:post, %r{/api/v1/videos\z})
          .to_return(status: 400, body: { detail: "invalid request" }.to_json)
      end

      it "marks the saved TTS scene failed with the generation" do
        call_result

        expect(service.ai_generation.ai_generation_scenes.sole.status).to eq("failed")
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

      it "returns the saved task without submitting or listing it again" do
        call_result

        expect(service).to be_success
        expect(service.task_id).to eq("mpt-task-existing")
        expect(video_request).not_to have_been_requested
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

      it "recovers the task ID without submitting the video request again" do
        call_result

        expect(service.task_id).to eq("mpt-task-recovered")
        expect(task_list_request).to have_been_requested.once
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

      it "persists the approved generation and attempt before the MPT request" do
        call_result

        expect(submission_observations[:input_snapshot]).to eq(generation_inputs.deep_stringify_keys)
        expect(submission_observations[:estimate_snapshot]).to eq(estimate.deep_stringify_keys)
        expect(submission_observations[:consent_snapshot]).to include(
          "confirmed" => true,
          "amount" => "0.50",
          "currency" => "USD"
        )
        expect(submission_observations[:attempt_status]).to eq("submitting")
        expect(
          a_request(:post, "http://mpt.test/api/v1/videos")
            .with(headers: { "x-task-id" => submission_observations[:correlation_id] })
        ).to have_been_made.once
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

      it "recovers the accepted task by request ID without submitting it again" do
        call_result

        expect(service).to be_success
        expect(service.ai_generation.reload.task_id).to eq("mpt-task-recovered")
        expect(video_request).to have_been_requested.once
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

        it "keeps both outcomes unknown and blocks a second submission after restart" do
          expect(service.ai_generation.reload.status).to eq("outcome_unknown")
          expect(service.ai_generation.workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
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

        it "keeps both outcomes unknown and blocks a second submission when the task list is unavailable" do
          expect(service.ai_generation.reload.status).to eq("outcome_unknown")
          expect(service.ai_generation.workflow_run.outbound_attempts.sole.status).to eq("outcome_unknown")
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

        it "finds the task on a later page without submitting the video again" do
          call_result

          expect(service.ai_generation.reload.task_id).to eq("mpt-task-recovered")
          expect(task_list_page_two_request).to have_been_requested.once
          expect(video_request).to have_been_requested.once
        end
      end
    end
  end
end
