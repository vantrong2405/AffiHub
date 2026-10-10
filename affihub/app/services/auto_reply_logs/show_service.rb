class AutoReplyLogs::ShowService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :event, :workflow_run, :outbound_attempt, :audit_events

  # Initializes a read request for one auto-reply comment log.
  #
  # @param event_id [Integer] the comment event to load
  # @return [AutoReplyLogs::ShowService] the configured service
  def initialize(event_id:)
    @event_id = event_id
    super()
  end

  # Loads the comment event and its immutable workflow audit history.
  #
  # @return [Boolean] whether the log and workflow exist
  def call
    step_load_event
    return false unless success?

    step_load_workflow
    return false unless success?

    step_load_outbound_attempt
    return false unless success?

    step_load_audit_events
    success?
  end

  private

  def step_load_event
    @event = AutoReplyEvent.includes(:social_destination).find_by(id: @event_id)
    return step_fail!("Không tìm thấy log tự trả lời.") unless event

    step_succeed!
  end

  def step_load_workflow
    @workflow_run = event.workflow_runs.find_by(
      operation: CONFIGURATION.fetch(:workflow_operation),
      stage: CONFIGURATION.fetch(:reply_stage)
    )
    return step_fail!("Không tìm thấy workflow của log tự trả lời.") unless workflow_run

    step_succeed!
  end

  def step_load_audit_events
    @audit_events = workflow_run.workflow_audit_events.order(:created_at, :id).to_a
    step_succeed!
  end

  def step_load_outbound_attempt
    @outbound_attempt = workflow_run.outbound_attempts
      .where(stage: CONFIGURATION.fetch(:reply_stage))
      .order(:attempt_number, :id)
      .last
    step_succeed!
  end
end
