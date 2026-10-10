require "rails_helper"

RSpec.describe AutoReplyLogsHelper, type: :helper do
  describe "#auto_reply_event_status_label" do
    it "returns a qualified label for an operator-confirmed occurrence" do
      expect(helper.auto_reply_event_status_label("manual_outcome_confirmed")).to eq(
        "Xác nhận thủ công: đã xảy ra; Meta chưa xác nhận."
      )
    end

    it "returns an unresolved label for an unknown provider outcome" do
      expect(helper.auto_reply_event_status_label("outcome_unknown")).to eq("Chưa xác định kết quả")
    end
  end

  describe "#auto_reply_attempt_status_label" do
    it "returns a Meta-confirmed label for a confirmed reply attempt" do
      expect(helper.auto_reply_attempt_status_label("confirmed")).to eq("Meta xác nhận đã tạo câu trả lời")
    end

    it "keeps manual occurrence separate from provider confirmation" do
      expect(helper.auto_reply_attempt_status_label("manual_outcome_confirmed")).to eq(
        "Người vận hành xác nhận đã xảy ra; Meta chưa xác nhận"
      )
    end
  end

  describe "#auto_reply_resolution_available?" do
    it "returns true when the comment and latest attempt remain unresolved" do
      auto_reply_event = build(:auto_reply_event, status: "outcome_unknown")
      outbound_attempt = build(:outbound_attempt, status: "outcome_unknown")

      expect(helper.auto_reply_resolution_available?(auto_reply_event, outbound_attempt)).to eq(true)
    end

    it "returns true when the latest attempt is still submitting" do
      auto_reply_event = build(:auto_reply_event, status: "outcome_unknown")
      outbound_attempt = build(:outbound_attempt, status: "submitting")

      expect(helper.auto_reply_resolution_available?(auto_reply_event, outbound_attempt)).to eq(true)
    end

    it "returns false when the latest attempt already has a final provider result" do
      auto_reply_event = build(:auto_reply_event, status: "outcome_unknown")
      outbound_attempt = build(:outbound_attempt, status: "confirmed")

      expect(helper.auto_reply_resolution_available?(auto_reply_event, outbound_attempt)).to eq(false)
    end

    it "returns false after the event has a manual resolution" do
      auto_reply_event = build(:auto_reply_event, status: "manual_outcome_confirmed")
      outbound_attempt = build(:outbound_attempt, status: "manual_outcome_confirmed")

      expect(helper.auto_reply_resolution_available?(auto_reply_event, outbound_attempt)).to eq(false)
    end
  end

  describe "#auto_reply_manual_decision_options" do
    it "returns the three configured manual outcomes in the audit workflow order" do
      expect(helper.auto_reply_manual_decision_options).to eq(
        [
          [ "Đã xảy ra", "occurred" ],
          [ "Chắc chắn chưa xảy ra", "not_occurred" ],
          [ "Vẫn chưa rõ", "unknown" ]
        ]
      )
    end
  end

  describe "#auto_reply_safe_error_message" do
    it "returns a safe explanation for the configured outcome-unknown error" do
      expect(helper.auto_reply_safe_error_message("auto_reply_outcome_unknown")).to eq(
        "Chưa xác định được Meta có nhận câu trả lời hay chưa."
      )
    end

    it "returns a safe fallback for an unrecognized error code" do
      expect(helper.auto_reply_safe_error_message("future_provider_error")).to eq(
        "Cần kiểm tra kết quả xử lý."
      )
    end

    it "returns nil when an audit event has no error code" do
      expect(helper.auto_reply_safe_error_message(nil)).to eq(nil)
    end
  end

  describe "#auto_reply_audit_display_fields" do
    it "returns populated audit details in display order" do
      audit_event = build(
        :workflow_audit_event,
        details: {
          "rule_snapshot" => { "rule_type" => "keyword", "keyword" => "bếp" },
          "reply_text" => "Chào bạn",
          "safe_error_code" => "auto_reply_outcome_unknown",
          "evidence" => "Đã kiểm tra bình luận",
          "provider_reference" => "reply-17"
        }
      )

      expect(helper.auto_reply_audit_display_fields(audit_event)).to eq(
        [
          { css_class: "text-sm text-base-content/70", prefix: "", value: "Quy tắc từ khóa · bếp" },
          { css_class: "whitespace-pre-wrap break-words rounded-box bg-base-200 p-3 text-sm", prefix: "", value: "Chào bạn" },
          { css_class: "text-sm text-error", prefix: "", value: "Chưa xác định được Meta có nhận câu trả lời hay chưa." },
          { css_class: "break-words text-sm text-base-content/70", prefix: "Bằng chứng: ", value: "Đã kiểm tra bình luận" },
          { css_class: "break-all text-sm text-base-content/70", prefix: "Mã tham chiếu: ", value: "reply-17" }
        ]
      )
    end

    it "returns no details when the audit event has no display fields" do
      audit_event = build(:workflow_audit_event, details: {})

      expect(helper.auto_reply_audit_display_fields(audit_event)).to eq([])
    end
  end
end
