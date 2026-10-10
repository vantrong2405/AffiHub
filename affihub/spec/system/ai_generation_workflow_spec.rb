# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AI generation workflow", type: :system do
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
    estimated_at = 1.minute.ago.iso8601
    {
      total_amount: "0.51",
      currency: "USD",
      required_costs_known: true,
      input_snapshot: generation_inputs,
      cost_breakdown: {
        muapi: { amount: "0.49", currency: "USD", provider: "MuAPI", source: "estimate-cost", estimated_at: estimated_at },
        llm: { amount: "0.01", currency: "USD", provider: "LLM", source: "Current estimate", estimated_at: estimated_at },
        stock: { amount: "0.00", currency: "USD", provider: "Pexels", source: "Pexels API license", estimated_at: estimated_at },
        tts_fallback: tts_fallback_quote,
        unknown: { amount: "0.00", currency: "USD", provider: "unknown", source: "none", estimated_at: estimated_at }
      }
    }
  end

  it "disables generation until an AI provider supports inference" do
    video_project = create(:video_project)

    visit video_project_path(video_project)
    click_link "Tạo video AI"

    expect(page).to have_text("Chưa có tài khoản AI sẵn sàng dùng model.")
    expect(page).to have_button("Tạo kịch bản", disabled: true)
    expect(video_project.ai_generations).to be_empty
  end

  it "submits a saved estimate after the user sets a budget and confirms consent" do
    video_project = create(:video_project)
    ai_generation = create(
      :ai_generation,
      video_project: video_project,
      status: :prompts_ready,
      input_snapshot: generation_inputs,
      estimate_snapshot: estimate_snapshot
    )
    video_request = stub_request(:post, %r{/api/v1/videos\z})
      .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-123" } }.to_json)

    visit edit_video_project_ai_generation_path(video_project, ai_generation)
    fill_in "Ngân sách tối đa (USD)", with: "1.00"
    check "Tôi duyệt báo giá và cho phép gửi job trả phí trong ngân sách này."
    click_button "Xác nhận ngân sách và tạo video"

    expect(page).to have_text("Đang tạo video bằng AI")
    expect(ai_generation.reload).to have_attributes(status: "processing", task_id: "mpt-task-123")
    expect(ai_generation.consent_snapshot).to include("budget" => "1.00", "confirmed" => true)
    expect(video_request).to have_been_requested.once
  end

  context "when a generation appears in project history" do
    let(:video_project) { create(:video_project) }
    let(:ai_generation) do
      create(
        :ai_generation,
        video_project: video_project,
        status: :prompts_ready,
        input_snapshot: generation_inputs
      )
    end

    before { ai_generation }

    it "opens the generation status from project history" do
      visit video_project_path(video_project)
      click_link "Xem trạng thái"

      expect(page).to have_text("A short summer skincare story.")
    end

    it "resumes scene approval from project history" do
      visit video_project_path(video_project)
      click_link "Tiếp tục"

      expect(page).to have_text("Gợi ý cảnh")
      expect(page).to have_button("Duyệt cảnh và lấy báo giá")
    end
  end

  context "when MPT has not yet confirmed the submitted job" do
    let(:video_project) { create(:video_project) }
    let(:ai_generation) do
      create(
        :ai_generation,
        video_project: video_project,
        status: :outcome_unknown,
        input_snapshot: generation_inputs,
        estimate_snapshot: estimate_snapshot
      )
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

    before { outbound_attempt }

    it "records a not occurred decision before offering a retry" do
      visit video_project_ai_generation_path(video_project, ai_generation)
      expect(page).to have_text("Chưa xác định được kết quả yêu cầu MPT.")
      expect(page).to have_select("Kết quả đối soát")
      select "Chắc chắn chưa xảy ra", from: "Kết quả đối soát"
      fill_in "Bằng chứng đối soát", with: "Không tìm thấy task trong danh sách MPT."
      check "Tôi đã kiểm tra bằng chứng và hiểu rủi ro chi phí nếu yêu cầu được gửi lại."
      click_button "Lưu quyết định đối soát"

      expect(page).to have_text("Đã ghi nhận job chưa xảy ra theo bằng chứng bạn cung cấp.")
      expect(page).to have_link("Xem lại ngân sách và xác nhận gửi lại")
      expect(ai_generation.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("manual_outcome_not_occurred")
      expect(workflow_run.reload.status).to eq("queued")
    end

    context "after the operator has confirmed that the previous request did not occur" do
      let(:workflow_run) do
        create(
          :workflow_run,
          workflowable: ai_generation,
          operation: "ai_video_generation",
          stage: "mpt_video_submission",
          status: "queued"
        )
      end
      let(:outbound_attempt) do
        create(
          :outbound_attempt,
          workflow_run: workflow_run,
          stage: "mpt_video_submission",
          status: "manual_outcome_not_occurred",
          sender_stopped_at: 2.minutes.ago,
          request_timeout_at: 1.minute.ago
        )
      end
      let(:video_request) do
        stub_request(:post, %r{/api/v1/videos\z})
          .to_return(status: 200, body: { status: 200, data: { task_id: "mpt-task-retried" } }.to_json)
      end

      before { video_request }

      it "reuses the saved generation after the user confirms a new budget" do
        visit edit_video_project_ai_generation_path(video_project, ai_generation)
        expect(page).to have_button("Xác nhận ngân sách và gửi lại video")
        fill_in "Ngân sách tối đa (USD)", with: "1.00"
        check "Tôi duyệt báo giá và cho phép gửi job trả phí trong ngân sách này."
        click_button "Xác nhận ngân sách và gửi lại video"

        expect(page).to have_text("Đang tạo video bằng AI")
        expect(ai_generation.reload).to have_attributes(status: "processing", task_id: "mpt-task-retried")
        expect(video_project.ai_generations.count).to eq(1)
        expect(workflow_run.reload.outbound_attempts.order(:attempt_number).pluck(:attempt_number, :status)).to eq(
          [ [ 1, "manual_outcome_not_occurred" ], [ 2, "confirmed" ] ]
        )
        expect(video_request).to have_been_requested.once
      end
    end
  end
end
