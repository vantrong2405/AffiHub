require "rails_helper"

RSpec.describe "Auto-reply logs", type: :request do
  describe "GET /auto_reply_logs" do
    it "returns the newest comment events" do
      create(:auto_reply_event)

      get auto_reply_logs_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /auto_reply_logs/:id" do
    it "returns the selected event with its workflow history" do
      auto_reply_event = create(:auto_reply_event)
      create(
        :workflow_run,
        workflowable: auto_reply_event,
        operation: "auto_reply",
        stage: "reply"
      )

      get auto_reply_log_path(auto_reply_event)

      expect(response).to have_http_status(:ok)
    end

    it "returns not found when the event does not exist" do
      get auto_reply_log_path(id: 99_999_999)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /auto_reply_logs/:id" do
    let(:auto_reply_event) { create(:auto_reply_event, status: "outcome_unknown") }
    let(:workflow_run) do
      create(
        :workflow_run,
        workflowable: auto_reply_event,
        operation: "auto_reply",
        stage: "reply",
        status: "outcome_unknown"
      )
    end
    let!(:outbound_attempt) do
      create(
        :outbound_attempt,
        workflow_run:,
        stage: "reply",
        status: "outcome_unknown",
        sender_stopped_at: 2.minutes.ago,
        request_timeout_at: 1.minute.ago
      )
    end

    it "persists manual confirmation without reporting a provider-confirmed reply" do
      patch auto_reply_log_path(auto_reply_event), params: {
        outcome_resolution: {
          decision: "occurred",
          evidence: "Đối chiếu reply với Meta",
          provider_reference: "https://facebook.com/comments/reply-1"
        }
      }

      expect(response).to redirect_to(auto_reply_log_path(auto_reply_event))
      expect(auto_reply_event.reload.status).to eq("manual_outcome_confirmed")
      expect(workflow_run.reload.status).to eq("completed")
      expect(outbound_attempt.reload.status).to eq("manual_outcome_confirmed")
    end

    it "enqueues a safe retry after confirmed non-occurrence and expired request timeout" do
      expect do
        patch auto_reply_log_path(auto_reply_event), params: {
          outcome_resolution: {
            decision: "not_occurred",
            evidence: "Đã kiểm tra Page, không thấy reply",
            risk_confirmed: "1"
          }
        }
      end.to have_enqueued_job(AutoResponder::ProcessJob)

      expect(response).to redirect_to(auto_reply_log_path(auto_reply_event))
      expect(auto_reply_event.reload.status).to eq("manual_outcome_not_occurred")
      expect(workflow_run.reload.status).to eq("queued")
    end

    it "keeps the event unresolved when the operator cannot determine the result" do
      patch auto_reply_log_path(auto_reply_event), params: {
        outcome_resolution: {
          decision: "unknown",
          evidence: "Chưa thể xác minh trên Meta"
        }
      }

      expect(response).to redirect_to(auto_reply_log_path(auto_reply_event))
      expect(auto_reply_event.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("outcome_unknown")
    end

    it "rejects non-occurrence without explicit retry-risk confirmation" do
      patch auto_reply_log_path(auto_reply_event), params: {
        outcome_resolution: {
          decision: "not_occurred",
          evidence: "Đã kiểm tra Page, không thấy reply",
          risk_confirmed: "0"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(auto_reply_event.reload.status).to eq("outcome_unknown")
      expect(workflow_run.reload.status).to eq("outcome_unknown")
      expect(outbound_attempt.reload.status).to eq("outcome_unknown")
    end
  end
end
