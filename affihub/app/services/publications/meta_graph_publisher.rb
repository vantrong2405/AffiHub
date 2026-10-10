class Publications::MetaGraphPublisher < ApplicationService
  CONFIGURATION = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers).fetch(:facebook)
  PUBLISH_STAGE = "publish"
  PROVIDER = "facebook"

  attr_reader :publication, :workflow_run, :outbound_attempt

  # Initializes the Meta publisher for a persisted publication workflow.
  #
  # @param workflow_run_id [Integer] the queued workflow to publish
  # @return [Publications::MetaGraphPublisher] the configured service
  def initialize(workflow_run_id:)
    @workflow_run_id = workflow_run_id
    super()
  end

  # Publishes a Reel or safely checks the status of an acknowledged Reel.
  #
  # @return [Boolean] whether the workflow completed or queued a status check
  def call
    return false unless step_load_workflow
    return step_succeed_for_published_publication if publication.published?
    return false unless step_validate_publication
    return false if step_block_unresolved_attempt
    return false unless step_claim_workflow

    step_process_publication
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_load_workflow
    @workflow_run = WorkflowRun.find_by(id: @workflow_run_id)
    return step_fail!("Không tìm thấy workflow đăng Publication.") unless workflow_run
    return step_fail!("Workflow không phải thao tác đăng Facebook Reel.") unless publish_workflow?

    @publication = workflow_run.workflowable
    return step_fail!("Không tìm thấy Publication cần đăng.") unless publication.is_a?(Publication)

    @checkpoint = workflow_run.checkpoint.to_h.stringify_keys
    @outbound_attempt = workflow_run.outbound_attempts.for_stage(PUBLISH_STAGE).first
    true
  end

  def publish_workflow?
    workflow_run.operation == "publication_publish" && workflow_run.stage == PUBLISH_STAGE
  end

  def step_succeed_for_published_publication
    step_succeed!
    success?
  end

  def step_validate_publication
    allowed_statuses = %w[approved uploading processing manual_outcome_not_occurred]
    return step_fail!("Publication chưa sẵn sàng để đăng.") unless allowed_statuses.include?(publication.status)
    return step_fail!("Chỉ hỗ trợ Facebook Page Reels.") unless social_destination.provider == PROVIDER
    return step_fail!("Facebook Page chưa kết nối.") unless social_destination.connected?
    return step_fail!("Facebook Page thiếu access token.") if social_destination.access_token.blank?
    return step_fail!("Render version chưa sẵn sàng hoặc thiếu file video.") unless render_file_ready?

    true
  end

  def render_file_ready?
    publication.render_version.ready? && publication.render_version.file.attached?
  end

  def step_block_unresolved_attempt
    return false unless outbound_attempt&.submitting? || outbound_attempt&.outcome_unknown?

    step_fail!("Outbound attempt cần được đối soát trước khi gửi lại.")
  end

  def step_claim_workflow
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: workflow_run.id,
      worker_id: worker_id,
      lease_duration: request_timeout + 30.seconds
    )
    return step_fail!(claim_service.errors.full_messages.to_sentence) unless claim_service.call

    @workflow_run = claim_service.workflow_run
    true
  end

  def step_process_publication
    return step_check_reel_status if status_check_ready?
    return false unless step_start_outbound_attempt
    return false unless step_start_reel_upload
    return false unless step_upload_reel
    return false unless step_finish_reel_upload

    step_check_reel_status
  end

  def status_check_ready?
    outbound_attempt&.confirmed? && @checkpoint["finish_acknowledged"] == true
  end

  def step_start_outbound_attempt
    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: workflow_run.id,
      worker_id: worker_id,
      fencing_token: workflow_run.fencing_token,
      stage: PUBLISH_STAGE,
      request_timeout_at: Time.current + request_timeout,
      idempotency_key: "publication-#{publication.id}-publish"
    )
    return step_fail!(start_service.errors.full_messages.to_sentence) unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    publication.update!(status: :uploading)
    true
  end

  def step_start_reel_upload
    response = meta_client.start_reel_upload(
      page_id: social_destination.external_id,
      page_access_token: social_destination.access_token
    )
    return step_mark_outcome_unknown("invalid_start_response") unless response.is_a?(Hash)

    @video_id = response["video_id"].presence
    @upload_url = response["upload_url"].presence
    return step_mark_outcome_unknown("invalid_start_response") unless @video_id && @upload_url

    @checkpoint = @checkpoint.merge("video_id" => @video_id)
    workflow_run.update!(checkpoint: @checkpoint)
    publication.update!(
      platform_post_id: @video_id,
      provider_reference: provider_reference
    )
    true
  rescue Meta::Client::Error => error
    step_handle_mutation_error(error)
  end

  def step_upload_reel
    response = nil
    render_version.file.open do |file|
      response = meta_client.upload_reel(
        upload_url: @upload_url,
        page_access_token: social_destination.access_token,
        file:,
        file_size: render_version.file.byte_size
      )
    end
    return step_mark_outcome_unknown("invalid_upload_response") unless response.is_a?(Hash)
    return step_mark_outcome_unknown("upload_not_confirmed") unless response["success"] == true

    @checkpoint = @checkpoint.merge("upload_complete" => true)
    workflow_run.update!(checkpoint: @checkpoint)
    true
  rescue Meta::Client::Error => error
    step_handle_mutation_error(error)
  end

  def step_finish_reel_upload
    response = meta_client.finish_reel_upload(
      page_id: social_destination.external_id,
      page_access_token: social_destination.access_token,
      video_id: @video_id,
      caption: publication.caption
    )
    return step_mark_outcome_unknown("invalid_finish_response") unless response.is_a?(Hash)
    return step_mark_outcome_unknown("finish_not_confirmed") unless response["success"] == true

    @checkpoint = @checkpoint.merge(
      "finish_acknowledged" => true,
      "status_poll_attempts" => 0
    )
    Publication.transaction do
      outbound_attempt.update!(
        status: :confirmed,
        sender_stopped_at: Time.current,
        provider_reference:
      )
      workflow_run.update!(checkpoint: @checkpoint)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: "meta_reel_publish_acknowledged",
        stage: PUBLISH_STAGE,
        details: { video_id: @video_id }
      )
    end
    true
  rescue Meta::Client::Error => error
    step_handle_mutation_error(error)
  end

  def step_check_reel_status
    @video_id = @checkpoint["video_id"] || publication.platform_post_id
    return step_mark_outcome_unknown("missing_video_id") if @video_id.blank?

    response = meta_client.reel_status(
      video_id: @video_id,
      page_access_token: social_destination.access_token
    )
    return step_mark_outcome_unknown("invalid_status_response") unless response.is_a?(Hash)
    return step_mark_failed("meta_reel_processing_failed") if reel_failed?(response)
    return step_mark_published(response) if reel_published?(response)

    step_schedule_status_check
  rescue Meta::Client::Error => error
    step_mark_outcome_unknown(error.code)
  end

  def reel_published?(response)
    reel_status = response["status"]
    return false unless reel_status.is_a?(Hash)

    publishing_phase = reel_status["publishing_phase"]
    return false unless publishing_phase.is_a?(Hash)

    reel_status["video_status"] == "ready" &&
      publishing_phase["status"] == "complete" &&
      valid_facebook_permalink?(response["permalink_url"])
  end

  def reel_failed?(response)
    reel_status = response["status"]
    return false unless reel_status.is_a?(Hash)

    publishing_phase = reel_status["publishing_phase"]
    reel_status["video_status"] == "error" ||
      (publishing_phase.is_a?(Hash) && publishing_phase["status"] == "error")
  end

  def valid_facebook_permalink?(permalink)
    return false if permalink.blank?

    uri = URI(permalink)
    uri.scheme == "https" && %w[facebook.com www.facebook.com m.facebook.com].include?(uri.host&.downcase) &&
      uri.port == 443 && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def step_mark_published(response)
    permalink = response["permalink_url"]
    Publication.transaction do
      publication.update!(
        status: :published,
        platform_post_id: @video_id,
        permalink:,
        published_at: Time.current,
        provider_reference:,
        safe_error_code: nil
      )
      outbound_attempt.update!(
        status: :confirmed,
        sender_stopped_at: Time.current,
        safe_error_code: nil,
        provider_reference:
      )
      workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: "meta_reel_published",
        stage: PUBLISH_STAGE,
        details: { video_id: @video_id, permalink: }
      )
    end
    step_succeed!
    success?
  end

  def step_schedule_status_check
    poll_attempts = @checkpoint.fetch("status_poll_attempts", 0).to_i + 1
    return step_mark_outcome_unknown("reel_status_not_final") if poll_attempts >= max_status_poll_attempts

    @checkpoint = @checkpoint.merge("status_poll_attempts" => poll_attempts)
    Publication.transaction do
      publication.update!(status: :processing, provider_reference:)
      workflow_run.update!(
        status: :queued,
        worker_id: nil,
        lease_expires_at: nil,
        checkpoint: @checkpoint
      )
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: "meta_reel_processing",
        stage: PUBLISH_STAGE,
        details: { status_poll_attempts: poll_attempts }
      )
    end
    Publications::PublishJob.set(wait: status_poll_interval).perform_later(workflow_run.id)
    step_succeed!
    success?
  end

  def step_mark_outcome_unknown(error_code)
    Publication.transaction do
      outbound_attempt.update!(
        status: :outcome_unknown,
        sender_stopped_at: Time.current,
        safe_error_code: error_code,
        provider_reference:
      )
      publication.update!(
        status: :outcome_unknown,
        platform_post_id: @video_id.presence || publication.platform_post_id,
        provider_reference:,
        safe_error_code: error_code
      )
      workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: "meta_reel_outcome_unknown",
        stage: PUBLISH_STAGE,
        details: { safe_error_code: error_code }
      )
    end
    step_fail!("Meta chưa xác nhận được kết quả đăng; cần đối soát trước khi thử lại.")
  end

  def step_mark_failed(error_code)
    Publication.transaction do
      outbound_attempt.update!(
        status: :failed,
        sender_stopped_at: Time.current,
        safe_error_code: error_code
      )
      publication.update!(status: :failed, safe_error_code: error_code)
      workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: "meta_reel_publish_failed",
        stage: PUBLISH_STAGE,
        details: { safe_error_code: error_code }
      )
    end
    step_fail!(error_code)
  end

  def step_handle_mutation_error(error)
    return step_mark_outcome_unknown(error.code) if ambiguous_provider_error?(error.code)

    step_mark_failed(error.code)
  end

  def ambiguous_provider_error?(error_code)
    error_code.in?(%w[graph_api_1 graph_api_2 network_request_failed invalid_json_response]) ||
      error_code.start_with?("graph_api_http_5")
  end

  def provider_reference
    { provider: PROVIDER, video_id: @video_id }.compact
  end

  def social_destination
    publication.social_destination
  end

  def render_version
    publication.render_version
  end

  def meta_client
    @meta_client ||= Meta::Client.new
  end

  def worker_id
    @worker_id ||= "meta-reels-#{SecureRandom.uuid}"
  end

  def request_timeout
    open_timeout = CONFIGURATION.fetch(:open_timeout_seconds).to_i
    read_timeout = CONFIGURATION.fetch(:read_timeout_seconds).to_i
    upload_timeout = CONFIGURATION.fetch(:upload_timeout_seconds).to_i
    upload_timeout + (read_timeout * 3) + (open_timeout * 4)
  end

  def status_poll_interval
    CONFIGURATION.fetch(:reel_status_poll_interval_seconds).to_i.seconds
  end

  def max_status_poll_attempts
    CONFIGURATION.fetch(:reel_status_max_poll_attempts).to_i
  end
end
