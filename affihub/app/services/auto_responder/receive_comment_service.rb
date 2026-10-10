class AutoResponder::ReceiveCommentService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys.fetch(:auto_responder)

  attr_reader :event, :workflow_run, :created

  # Initializes the persistence request for one provider comment event.
  #
  # @param social_destination_id [Integer] the destination that received the comment
  # @param source [String] the provider that sent the event
  # @param event_type [String] the provider event type
  # @param provider_comment_id [String] the provider's stable comment identifier
  # @param comment_text [String] the comment text used for matching
  # @return [AutoResponder::ReceiveCommentService] the configured service
  def initialize(social_destination_id:, source:, event_type:, provider_comment_id:, comment_text:)
    @social_destination_id = social_destination_id
    @source = source.to_s
    @event_type = event_type.to_s
    @provider_comment_id = provider_comment_id.to_s
    @comment_text = comment_text.to_s
    @created = false
    super()
  end

  # Persists one deduplicated comment event and its reply workflow.
  #
  # @return [Boolean] whether the event was accepted or already persisted
  def call
    return false unless step_validate_comment

    step_persist_event_and_workflow
    return false unless success?

    step_enqueue_workflow if created
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_validate_comment
    @social_destination = SocialDestination.find_by(id: @social_destination_id)
    return step_fail!("Không tìm thấy đích nhận bình luận.") unless @social_destination
    return step_fail!("Nguồn hoặc loại sự kiện bình luận không được hỗ trợ.") unless step_supported_event?
    return step_fail!("Bình luận thiếu mã định danh hoặc nội dung.") if @provider_comment_id.blank? || @comment_text.blank?

    true
  end

  def step_persist_event_and_workflow
    AutoReplyEvent.transaction do
      @social_destination = SocialDestination.lock.find(@social_destination.id)
      @event = @social_destination.auto_reply_events.find_by(provider_comment_id: @provider_comment_id)
      if event.nil?
        step_create_event
        @created = true
      end
      step_find_or_create_workflow
      step_record_received_event if created
    end
    step_succeed!
  end

  def step_supported_event?
    provider_configuration = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers)
    provider_configuration.key?(@source.to_sym) &&
      @social_destination.provider == @source &&
      @event_type == CONFIGURATION.fetch(:comment_event_type)
  end

  def step_create_event
    @event = @social_destination.auto_reply_events.create!(
      source: @source,
      event_type: @event_type,
      provider_comment_id: @provider_comment_id,
      comment_text: @comment_text
    )
  end

  def step_find_or_create_workflow
    workflow_configuration = {
      operation: CONFIGURATION.fetch(:workflow_operation),
      stage: CONFIGURATION.fetch(:reply_stage)
    }
    @workflow_run = event.workflow_runs.find_by(workflow_configuration)
    return if workflow_run

    @workflow_run = event.workflow_runs.create!(
      operation_id: SecureRandom.uuid,
      **workflow_configuration
    )
    @created = true
  end

  def step_record_received_event
    workflow_run.workflow_audit_events.create!(
      event_type: CONFIGURATION.fetch(:audit_events).fetch(:comment_received),
      stage: workflow_run.stage,
      details: {
        source: @source,
        event_type: @event_type,
        social_destination_id: @social_destination.id,
        provider_comment_id: @provider_comment_id,
        comment_text: @comment_text
      }
    )
  end

  def step_enqueue_workflow
    AutoResponder::ProcessJob.perform_later(workflow_run.id)
  end
end
