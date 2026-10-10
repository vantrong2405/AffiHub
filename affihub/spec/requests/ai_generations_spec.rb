# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI video generation pages", type: :request do
  let(:video_project) { create(:video_project) }
  let(:ai_provider_connection) do
    create(
      :ai_provider_connection,
      provider: "codex",
      status: :pending_verification,
      available_models: [],
      selected_model: nil
    )
  end
  let(:script_inputs) do
    {
      topic: "Summer skincare",
      language: "vi",
      tone: "friendly",
      target_duration: 30,
      ai_provider_connection_id: ai_provider_connection.id
    }
  end
  let(:mpt_script_request) do
    stub_request(:post, "http://mpt.test/api/v1/scripts")
      .to_return(status: 200, body: { status: 200, data: { video_script: "must not be used" } }.to_json)
  end

  describe "GET /video_projects/:video_project_id/ai_generations/new" do
    it "returns the AI generation form for the selected project" do
      get new_video_project_ai_generation_path(video_project)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/ai_generations/:id/edit" do
    it "returns the selected AI generation page" do
      ai_generation = create(:ai_generation, video_project: video_project)

      get edit_video_project_ai_generation_path(video_project, ai_generation)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /video_projects/:video_project_id/ai_generations/:id" do
    it "returns the selected AI generation status page" do
      ai_generation = create(:ai_generation, video_project: video_project)

      get video_project_ai_generation_path(video_project, ai_generation)

      expect(response).to have_http_status(:ok)
    end

    it "returns not found when the generation belongs to another project" do
      ai_generation = create(:ai_generation)

      get video_project_ai_generation_path(video_project, ai_generation)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /video_projects/:video_project_id/ai_generations" do
    before do
      mpt_script_request
    end

    it "returns an unprocessable response while Codex inference is unverified" do
      expect do
        post video_project_ai_generations_path(video_project), params: { ai_generation: script_inputs }
      end.not_to change(AiGeneration, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to match(Regexp.escape("Nhà cung cấp này chưa hỗ trợ tạo nội dung."))
      expect(mpt_script_request).not_to have_been_requested
    end

    context "when the topic is blank" do
      let(:script_inputs) { super().merge(topic: " ") }

      it "returns an unprocessable response without requesting a script" do
        expect do
          post video_project_ai_generations_path(video_project), params: { ai_generation: script_inputs }
        end.not_to change(AiGeneration, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(mpt_script_request).not_to have_been_requested
      end
    end
  end

  describe "PATCH /video_projects/:video_project_id/ai_generations/:id submit" do
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
    let(:estimate_snapshot) do
      {
        total_amount: "0.50",
        currency: "USD",
        required_costs_known: true,
        input_snapshot: generation_inputs,
        cost_breakdown: { tts_fallback: tts_fallback_quote }
      }
    end
    let(:ai_generation) do
      create(
        :ai_generation,
        video_project: video_project,
        status: :prompts_ready,
        input_snapshot: generation_inputs,
        estimate_snapshot: estimate_snapshot
      )
    end
    let(:video_request) do
      stub_request(:post, %r{/api/v1/videos\z})
        .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json)
    end

    before { video_request }

    it "submits the saved generation after confirming its current estimate" do
      ai_generation

      expect do
        patch video_project_ai_generation_path(video_project, ai_generation),
          params: { ai_generation: { step: "submit", budget: "1.00", confirmed: "1" } }
      end.not_to change(AiGeneration, :count)

      expect(response).to redirect_to(video_project_ai_generation_path(video_project, ai_generation))
      expect(ai_generation.reload).to have_attributes(status: "processing", task_id: "mpt-task-123")
      expect(ai_generation.consent_snapshot.slice("confirmed", "amount", "currency")).to eq(
        "confirmed" => true,
        "amount" => "0.50",
        "currency" => "USD"
      )
      expect(video_request).to have_been_requested.once
    end
  end

  describe "PATCH /video_projects/:video_project_id/ai_generations/:id resolve outcome" do
    let(:ai_generation) do
      create(:ai_generation, video_project: video_project, status: :outcome_unknown)
    end
    let(:workflow_run) do
      create(
        :workflow_run,
        workflowable: ai_generation,
        operation: "ai_video_generation",
        stage: "mpt_video_submission",
        status: "reconciliation_required"
      )
    end
    let(:outbound_attempt) do
      create(
        :outbound_attempt,
        workflow_run: workflow_run,
        stage: "mpt_video_submission",
        status: "outcome_unknown",
        sender_stopped_at: 2.minutes.ago,
        request_timeout_at: 1.minute.ago
      )
    end
    let(:decision) { "unknown" }
    let(:evidence) { "Task list hiện chưa xác định được request." }
    let(:provider_reference) { nil }
    let(:risk_confirmed) { "1" }

    before { outbound_attempt }

    it "records an unknown decision and keeps the generation blocked" do
      patch video_project_ai_generation_path(video_project, ai_generation),
        params: {
          ai_generation: {
            step: "resolve_outcome",
            decision: decision,
            evidence: evidence,
            provider_reference: provider_reference,
            risk_confirmed: risk_confirmed
          }
        }

      expect(response).to redirect_to(video_project_ai_generation_path(video_project, ai_generation))
      expect(ai_generation.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.manual_evidence).to eq(evidence)
      expect(outbound_attempt.workflow_run.workflow_audit_events.sole.details.slice("decision", "evidence")).to eq(
        "decision" => "unknown",
        "evidence" => evidence
      )
    end

    context "when the operator confirms that the request did not occur" do
      let(:decision) { "not_occurred" }
      let(:evidence) { "Không tìm thấy task trong danh sách MPT." }

      it "requeues the workflow after recording the retry risk and evidence" do
        patch video_project_ai_generation_path(video_project, ai_generation),
          params: {
            ai_generation: {
              step: "resolve_outcome",
              decision: decision,
              evidence: evidence,
              risk_confirmed: risk_confirmed
            }
          }

        expect(response).to redirect_to(video_project_ai_generation_path(video_project, ai_generation))
        expect(outbound_attempt.reload.status).to eq("manual_outcome_not_occurred")
        expect(outbound_attempt.workflow_run.reload.status).to eq("queued")
        expect(outbound_attempt.workflow_run.workflow_audit_events.sole.details.slice("decision", "risk_confirmed")).to eq(
          "decision" => "not_occurred",
          "risk_confirmed" => true
        )
        expect(ai_generation.reload.status).to eq("outcome_unknown")
      end
    end

    context "when the operator confirms that the request occurred" do
      let(:decision) { "occurred" }
      let(:evidence) { "Task đã xuất hiện trong dashboard MPT." }
      let(:provider_reference) { "mpt-task-123" }

      it "stores the provider reference without marking the generation completed" do
        patch video_project_ai_generation_path(video_project, ai_generation),
          params: {
            ai_generation: {
              step: "resolve_outcome",
              decision: decision,
              evidence: evidence,
              provider_reference: provider_reference,
              risk_confirmed: risk_confirmed
            }
          }

        expect(response).to redirect_to(video_project_ai_generation_path(video_project, ai_generation))
        expect(outbound_attempt.reload.status).to eq("manual_outcome_confirmed")
        expect(outbound_attempt.provider_reference.slice("manual_reference")).to eq("manual_reference" => provider_reference)
        expect(ai_generation.reload.status).to eq("outcome_unknown")
      end
    end
  end

  describe "PATCH /video_projects/:video_project_id/ai_generations/:id" do
    let(:ai_provider_connection) do
      create(
        :ai_provider_connection,
        provider: "codex",
        status: :pending_verification,
        available_models: [],
        selected_model: nil
      )
    end
    let(:ai_generation) do
      create(
        :ai_generation,
        video_project: video_project,
        status: :script_ready,
        input_snapshot: {
          video_subject: "Summer skincare",
          ai_provider_connection_id: ai_provider_connection.id,
          llm_provider: "codex",
          llm_model: nil,
          video_script: "A short summer skincare story.",
          scene_count: 2,
          scene_duration: 6,
          resolution: "480p",
          scenes: []
        }
      )
    end
    let(:terms_request) do
      stub_request(:post, "http://mpt.test/api/v1/terms")
        .to_return(status: 200, body: { status: 200, data: { video_terms: [ "must not be used" ] } }.to_json)
    end
    let(:update_params) do
      {
        step: "create_prompts",
        video_script: "A short summer skincare story.",
        script_approved: "1"
      }
    end

    before do
      terms_request
    end

    it "returns an unprocessable response while Codex inference is unverified" do
      expect(Codex::Client).not_to receive(:new)

      patch video_project_ai_generation_path(video_project, ai_generation),
        params: { ai_generation: update_params }

      expect(response).to have_http_status(:unprocessable_content)
      expect(ai_generation.reload.status).to eq("script_ready")
      expect(ai_generation.input_snapshot.fetch("script_approved")).to eq(true)
      expect(ai_generation.input_snapshot.fetch("scenes")).to eq([])
      expect(response.body).to match(Regexp.escape("Nhà cung cấp này chưa hỗ trợ tạo nội dung."))
      expect(terms_request).not_to have_been_requested
    end

    context "when the script is not approved" do
      let(:update_params) { super().merge(script_approved: "0") }

      it "returns an unprocessable response without requesting scene prompts" do
        patch video_project_ai_generation_path(video_project, ai_generation),
          params: { ai_generation: update_params }

        expect(response).to have_http_status(:unprocessable_content)
        expect(ai_generation.reload.status).to eq("script_ready")
        expect(terms_request).not_to have_been_requested
      end
    end

    context "when the user requests a scene estimate" do
      let(:first_estimate_request) do
        stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
          .with(body: {
            "prompt" => "A sunny bathroom",
            "duration" => 6,
            "resolution" => "480p",
            "aspect_ratio" => "9:16"
          })
          .to_return(status: 200, body: { cost: "0.20", currency: "USD" }.to_json)
      end
      let(:second_estimate_request) do
        stub_request(:post, %r{/models/seedance-lite-t2v/estimate-cost\z})
          .with(body: {
            "prompt" => "A skincare bottle",
            "duration" => 6,
            "resolution" => "480p",
            "aspect_ratio" => "9:16"
          })
          .to_return(status: 200, body: { cost: "0.30", currency: "USD" }.to_json)
      end
      let(:estimate_snapshot) { {} }
      let(:ai_generation) do
        create(
          :ai_generation,
          video_project: video_project,
          status: :prompts_ready,
          input_snapshot: {
            video_subject: "Summer skincare",
            video_script: "A short summer skincare story.",
            model_id: "seedance-lite-t2v",
            resolution: "480p",
            scene_count: 2,
            scenes: [
              { prompt: "A sunny bathroom", duration: 6, approved: true },
              { prompt: "A skincare bottle", duration: 6, approved: true }
            ]
          },
          estimate_snapshot: estimate_snapshot
        )
      end
      let(:scene_inputs) do
        [
          { prompt: "A sunny bathroom", duration: "6", approved: "1" },
          { prompt: "A skincare bottle", duration: "6", approved: "1" }
        ]
      end
      let(:estimate_params) { { step: "create_estimate", scenes: scene_inputs } }

      before do
        first_estimate_request
        second_estimate_request
      end

      it "saves the current estimate without submitting a paid video job" do
        patch video_project_ai_generation_path(video_project, ai_generation),
          params: { ai_generation: estimate_params }

        expect(response).to redirect_to(edit_video_project_ai_generation_path(video_project, ai_generation))
        expect(ai_generation.reload.estimate_snapshot.dig("cost_breakdown", "muapi", "amount")).to eq("0.5")
        expect(ai_generation.estimate_snapshot.fetch("required_costs_known")).to eq(false)
        expect(first_estimate_request).to have_been_requested.once
        expect(second_estimate_request).to have_been_requested.once
      end

      context "when one scene is not approved" do
        let(:scene_inputs) do
          [ super().first.merge(approved: "0"), super().last ]
        end
        let(:estimate_snapshot) { { total_amount: "0.50" } }

        it "clears the previous estimate without requesting provider quotes" do
          patch video_project_ai_generation_path(video_project, ai_generation),
            params: { ai_generation: estimate_params }

          expect(response).to have_http_status(:unprocessable_content)
          expect(ai_generation.reload.estimate_snapshot).to eq({})
          expect(first_estimate_request).not_to have_been_requested
          expect(second_estimate_request).not_to have_been_requested
        end
      end
    end
  end
end
