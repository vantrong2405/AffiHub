module AutoReplyLogsHelper
  AUTO_REPLY_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:auto_responder)
  STATUS_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:auto_reply_event)
  EVENT_STATUSES = STATUS_CONFIGURATION.fetch(:values)
  AUDIT_EVENTS = AUTO_REPLY_CONFIGURATION.fetch(:audit_events)
  MANUAL_DECISIONS = AUTO_REPLY_CONFIGURATION.fetch(:manual_decisions)
  RULE_TYPES = AUTO_REPLY_CONFIGURATION.fetch(:rule_types)
  SAFE_ERROR_CODES = AUTO_REPLY_CONFIGURATION.fetch(:safe_error_codes)
  MANUAL_DECISION_LABELS = {
    MANUAL_DECISIONS.fetch(:occurred) => "Đã xảy ra",
    MANUAL_DECISIONS.fetch(:not_occurred) => "Chắc chắn chưa xảy ra",
    MANUAL_DECISIONS.fetch(:unknown) => "Vẫn chưa rõ"
  }.freeze

  STATUS_LABELS = {
    EVENT_STATUSES.fetch(:queued) => "Đang chờ xử lý",
    EVENT_STATUSES.fetch(:sent) => "Meta xác nhận đã trả lời",
    EVENT_STATUSES.fetch(:failed) => "Trả lời thất bại",
    EVENT_STATUSES.fetch(:outcome_unknown) => "Chưa xác định kết quả",
    EVENT_STATUSES.fetch(:manual_outcome_confirmed) => "Xác nhận thủ công: đã xảy ra; Meta chưa xác nhận.",
    EVENT_STATUSES.fetch(:manual_outcome_not_occurred) => "Xác nhận thủ công: chưa xảy ra"
  }.freeze
  STATUS_BADGE_CLASSES = {
    EVENT_STATUSES.fetch(:queued) => "badge-info",
    EVENT_STATUSES.fetch(:sent) => "badge-success",
    EVENT_STATUSES.fetch(:failed) => "badge-error",
    EVENT_STATUSES.fetch(:outcome_unknown) => "badge-warning",
    EVENT_STATUSES.fetch(:manual_outcome_confirmed) => "badge-info",
    EVENT_STATUSES.fetch(:manual_outcome_not_occurred) => "badge-neutral"
  }.freeze
  OUTBOUND_ATTEMPT_STATUSES = Rails.application.config_for(:video_workflow).deep_symbolize_keys
    .fetch(:statuses)
    .fetch(:outbound_attempt)
    .fetch(:values)
  ATTEMPT_STATUS_LABELS = {
    OUTBOUND_ATTEMPT_STATUSES.fetch(:prepared) => "Đã chuẩn bị",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:submitting) => "Đang gửi yêu cầu",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:confirmed) => "Meta xác nhận đã tạo câu trả lời",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:failed) => "Không gửi được",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:outcome_unknown) => "Chưa rõ kết quả",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:manual_outcome_confirmed) => "Người vận hành xác nhận đã xảy ra; Meta chưa xác nhận",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:manual_outcome_not_occurred) => "Người vận hành xác nhận chưa xảy ra"
  }.freeze
  ATTEMPT_STATUS_BADGE_CLASSES = {
    OUTBOUND_ATTEMPT_STATUSES.fetch(:prepared) => "badge-neutral",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:submitting) => "badge-info",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:confirmed) => "badge-success",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:failed) => "badge-error",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:outcome_unknown) => "badge-warning",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:manual_outcome_confirmed) => "badge-info",
    OUTBOUND_ATTEMPT_STATUSES.fetch(:manual_outcome_not_occurred) => "badge-neutral"
  }.freeze
  SAFE_ERROR_MESSAGES = {
    SAFE_ERROR_CODES.fetch(:comment_destination_missing) => "Đích kết nối đã ngắt trước khi gửi câu trả lời.",
    SAFE_ERROR_CODES.fetch(:comment_payload_invalid) => "Thông tin comment nhận được không đủ để xử lý.",
    SAFE_ERROR_CODES.fetch(:default_rule_missing) => "Câu trả lời mặc định đã bị tắt hoặc thay đổi trước khi gửi.",
    SAFE_ERROR_CODES.fetch(:reply_response_invalid) => "Meta trả về phản hồi không đủ để xác nhận.",
    SAFE_ERROR_CODES.fetch(:reply_failed) => "Meta từ chối yêu cầu trả lời bình luận.",
    SAFE_ERROR_CODES.fetch(:reply_outcome_unknown) => "Chưa xác định được Meta có nhận câu trả lời hay chưa.",
    SAFE_ERROR_CODES.fetch(:network_request_failed) => "Kết nối bị gián đoạn trước khi nhận kết quả từ Meta.",
    SAFE_ERROR_CODES.fetch(:invalid_json_response) => "Phản hồi từ Meta không đọc được.",
    SAFE_ERROR_CODES.fetch(:worker_lease_lost) => "Worker mất quyền xử lý trước khi gửi câu trả lời."
  }.freeze

  # Returns a Vietnamese label for an auto-reply event status.
  #
  # @param status [String, Symbol] the configured auto-reply event status
  # @return [String] the user-facing status label
  def auto_reply_event_status_label(status)
    STATUS_LABELS.fetch(status.to_s, "Trạng thái khác")
  end

  # Reports whether an event has an unresolved provider outcome.
  #
  # @param auto_reply_event [AutoReplyEvent] the comment event
  # @return [Boolean] whether the event is outcome unknown
  def auto_reply_outcome_unknown?(auto_reply_event)
    auto_reply_event&.outcome_unknown? || false
  end

  # Reports whether an event has a safe error to explain.
  #
  # @param auto_reply_event [AutoReplyEvent] the comment event
  # @return [Boolean] whether the event has a machine error code
  def auto_reply_event_error_present?(auto_reply_event)
    auto_reply_event&.safe_error_code.present?
  end

  # Reports whether a latest reply attempt exists for display.
  #
  # @param outbound_attempt [OutboundAttempt, nil] the latest reply attempt
  # @return [Boolean] whether an attempt is available
  def auto_reply_attempt_present?(outbound_attempt)
    outbound_attempt.present?
  end

  # Reports whether an event has audit entries to display.
  #
  # @param audit_events [Array<WorkflowAuditEvent>] append-only history
  # @return [Boolean] whether the history contains entries
  def auto_reply_audit_events_present?(audit_events)
    audit_events.present?
  end

  # Reports whether the log index has comment events to display.
  #
  # @param auto_reply_events [Array<AutoReplyEvent>] events loaded for the index
  # @return [Boolean] whether at least one event is available
  def auto_reply_events_present?(auto_reply_events)
    auto_reply_events.present?
  end

  # Returns the daisyUI badge tone for an auto-reply event status.
  #
  # @param status [String, Symbol] the configured auto-reply event status
  # @return [String] a daisyUI badge tone class
  def auto_reply_event_status_badge_class(status)
    STATUS_BADGE_CLASSES.fetch(status.to_s, "badge-ghost")
  end

  # Returns a Vietnamese label for an outbound reply attempt status.
  #
  # @param status [String, Symbol] the configured outbound attempt status
  # @return [String] the user-facing attempt status label
  def auto_reply_attempt_status_label(status)
    ATTEMPT_STATUS_LABELS.fetch(status.to_s, "Trạng thái yêu cầu khác")
  end

  # Returns the daisyUI badge tone for an outbound reply attempt status.
  #
  # @param status [String, Symbol] the configured outbound attempt status
  # @return [String] a daisyUI badge tone class
  def auto_reply_attempt_status_badge_class(status)
    ATTEMPT_STATUS_BADGE_CLASSES.fetch(status.to_s, "badge-ghost")
  end

  # Reports whether the log can accept an operator decision for its active attempt.
  #
  # @param auto_reply_event [AutoReplyEvent] the comment event
  # @param outbound_attempt [OutboundAttempt, nil] the latest reply attempt
  # @return [Boolean] whether the outcome can be reconciled
  def auto_reply_resolution_available?(auto_reply_event, outbound_attempt)
    return false unless auto_reply_event&.outcome_unknown? && outbound_attempt

    unresolved_statuses = %i[submitting outcome_unknown].map do |status|
      OUTBOUND_ATTEMPT_STATUSES.fetch(status)
    end
    unresolved_statuses.include?(outbound_attempt.status)
  end

  # Returns the three operator decisions accepted for an unknown outcome.
  #
  # @return [Array<Array<String>>] labels and configured decision values
  def auto_reply_manual_decision_options
    MANUAL_DECISION_LABELS.map { |decision, label| [ label, decision ] }
  end

  # Returns a safe Vietnamese explanation for a stored machine error code.
  #
  # @param safe_error_code [String, Symbol, nil] the machine-readable error code
  # @return [String, nil] the safe explanation when an error code is present
  def auto_reply_safe_error_message(safe_error_code)
    return if safe_error_code.blank?

    SAFE_ERROR_MESSAGES.fetch(safe_error_code.to_s, "Cần kiểm tra kết quả xử lý.")
  end

  # Returns a Vietnamese summary of one append-only auto-reply audit event.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String] the user-facing audit summary
  def auto_reply_audit_description(audit_event)
    case audit_event.event_type
    when AUDIT_EVENTS.fetch(:comment_received) then "Đã nhận comment và đưa vào hàng đợi."
    when AUDIT_EVENTS.fetch(:sent) then "Meta xác nhận đã tạo câu trả lời."
    when AUDIT_EVENTS.fetch(:failed) then "Không thể gửi câu trả lời."
    when AUDIT_EVENTS.fetch(:outcome_unknown) then "Kết quả gửi chưa xác định."
    when AUDIT_EVENTS.fetch(:manual_outcome_resolved) then auto_reply_manual_decision_label(audit_event.details.to_h["decision"])
    else "Đã ghi nhận một thay đổi trong quy trình."
    end
  end

  # Returns the reply text captured in one audit event, when available.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String, nil] the captured static reply text
  def auto_reply_audit_reply_text(audit_event)
    audit_event.details.to_h["reply_text"]
  end

  # Returns manual evidence captured in one audit event, when available.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String, nil] the redacted operator evidence
  def auto_reply_audit_evidence(audit_event)
    audit_event.details.to_h["evidence"]
  end

  # Returns a user-safe explanation stored with one audit event.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String, nil] the mapped error explanation
  def auto_reply_audit_error_message(audit_event)
    auto_reply_safe_error_message(audit_event.details.to_h["safe_error_code"])
  end

  # Returns the provider reference or reply ID saved with one audit event.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String, nil] the stored provider reference
  def auto_reply_audit_provider_reference(audit_event)
    details = audit_event.details.to_h
    details["provider_reference"] || details["provider_reply_id"]
  end

  # Returns the rule snapshot captured when a reply was attempted.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [Hash, nil] the immutable rule snapshot
  def auto_reply_audit_rule_snapshot(audit_event)
    audit_event.details.to_h["rule_snapshot"]
  end

  # Returns a readable summary of the rule used for a reply attempt.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [String, nil] the rule type and keyword when captured
  def auto_reply_audit_rule_summary(audit_event)
    rule_snapshot = auto_reply_audit_rule_snapshot(audit_event)
    return unless rule_snapshot

    rule_type_label = if rule_snapshot.fetch("rule_type") == RULE_TYPES.fetch(:keyword)
      "Quy tắc từ khóa"
    else
      "Câu trả lời mặc định"
    end
    keyword = rule_snapshot["keyword"]
    keyword.present? ? "#{rule_type_label} · #{keyword}" : rule_type_label
  end

  # Returns populated audit values with the presentation data needed by the log detail.
  #
  # @param audit_event [WorkflowAuditEvent] the saved audit event
  # @return [Array<Hash>] populated audit fields in their display order
  def auto_reply_audit_display_fields(audit_event)
    fields = [
      {
        css_class: "text-sm text-base-content/70",
        prefix: "",
        value: auto_reply_audit_rule_summary(audit_event)
      },
      {
        css_class: "whitespace-pre-wrap break-words rounded-box bg-base-200 p-3 text-sm",
        prefix: "",
        value: auto_reply_audit_reply_text(audit_event)
      },
      {
        css_class: "text-sm text-error",
        prefix: "",
        value: auto_reply_audit_error_message(audit_event)
      },
      {
        css_class: "break-words text-sm text-base-content/70",
        prefix: "Bằng chứng: ",
        value: auto_reply_audit_evidence(audit_event)
      },
      {
        css_class: "break-all text-sm text-base-content/70",
        prefix: "Mã tham chiếu: ",
        value: auto_reply_audit_provider_reference(audit_event)
      }
    ]

    fields.select { |field| field.fetch(:value).present? }
  end

  private

  def auto_reply_manual_decision_label(decision)
    case decision
    when MANUAL_DECISIONS.fetch(:occurred) then "Người vận hành xác nhận câu trả lời đã xảy ra."
    when MANUAL_DECISIONS.fetch(:not_occurred) then "Người vận hành xác nhận câu trả lời chưa xảy ra."
    when MANUAL_DECISIONS.fetch(:unknown) then "Người vận hành vẫn chưa xác định được kết quả."
    else "Người vận hành đã lưu quyết định đối soát."
    end
  end
end
