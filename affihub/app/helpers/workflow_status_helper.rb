module WorkflowStatusHelper
  # Renders a consistent translated badge for a workflow status.
  #
  # @param status [String, Symbol] the stored workflow status
  # @param resource [String] the status translation namespace
  # @return [ActiveSupport::SafeBuffer] the status badge
  def workflow_status_badge(status, resource:)
    badge_class = case status.to_s
    when "ready", "completed", "published", "confirmed"
      "badge-success"
    when "failed", "outcome_unknown", "reconciliation_required"
      "badge-error"
    when "processing", "running", "submitting"
      "badge-info"
    when "pending", "queued", "draft", "prepared"
      "badge-warning"
    else
      "badge-neutral"
    end
    label = I18n.t("video_workflow.statuses.#{resource}.#{status}", default: status.to_s.humanize)

    content_tag(:span, label, class: [ "badge", badge_class ])
  end
end
