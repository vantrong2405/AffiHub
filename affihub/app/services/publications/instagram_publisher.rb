class Publications::InstagramPublisher < ApplicationService
  attr_reader :publication, :workflow_run, :outbound_attempt

  # Initializes the publisher for one persisted Instagram Publication workflow.
  #
  # @param workflow_run_id [Integer] the queued Instagram publication workflow
  # @return [Publications::InstagramPublisher] the configured service
  def initialize(workflow_run_id:)
    @workflow_run_id = workflow_run_id
    @configuration = Rails.application.config_for(:meta).deep_symbolize_keys.fetch(:providers).fetch(:instagram)
    super()
  end

  # Uploads a local Reel, reconciles its container, and publishes the approved media.
  #
  # @return [Boolean] whether the workflow completed or queued a status check
  def call
    return false unless step_load_workflow
    return step_succeed_for_published_publication if publication.published?
    return step_reconcile_unknown if outbound_attempt&.outcome_unknown?
    return false unless step_validate_publication
    return false if outbound_attempt&.submitting? && !@checkpoint["upload_started"]
    return false unless step_check_publishing_limit if @checkpoint["creation_id"].blank?
    return false unless step_claim_workflow
    return false unless step_start_container unless @checkpoint["creation_id"].present?
    return false unless step_upload_video unless upload_started_or_complete?

    step_check_container_status
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  rescue Meta::Client::Error => error
    step_handle_client_error(error)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse
    step_handle_client_error(Meta::Client::Error.new(client_error_code(:network_request_failed)))
  end

  private

  def step_load_workflow
    @workflow_run = WorkflowRun.find_by(id: @workflow_run_id)
    return step_fail!("Không tìm thấy workflow đăng Instagram.") unless workflow_run
    return step_fail!("Workflow không phải thao tác đăng Instagram.") unless publish_workflow?

    @publication = workflow_run.workflowable
    return step_fail!("Không tìm thấy Publication cần đăng.") unless publication.is_a?(Publication)

    @social_destination = publication.social_destination
    @social_connection = @social_destination.social_connection
    @render_version = publication.render_version
    @checkpoint = workflow_run.checkpoint.to_h.stringify_keys
    @outbound_attempt = workflow_run.outbound_attempts.for_stage(publish_stage).first
    true
  end

  def step_succeed_for_published_publication
    step_succeed!
    success?
  end

  def publish_workflow?
    workflow_run.operation == @configuration.fetch(:publication_operation) &&
      workflow_run.stage == publish_stage
  end

  def step_validate_publication
    return step_fail!("Publication chưa sẵn sàng để đăng.") unless publication_ready?
    return step_record_pre_send_failure(:business_account_required) unless instagram_destination_ready?
    return step_record_pre_send_failure(:source_not_ready) unless render_file_ready?

    true
  end

  def publication_ready?
    publication.approved? || publication.uploading? || publication.processing? || publication.manual_outcome_not_occurred?
  end

  def instagram_destination_ready?
    metadata = @social_destination.metadata.to_h.stringify_keys
    @social_destination.provider == "instagram" && @social_connection.connected? && @social_destination.connected? &&
      metadata["page_id"].present? && metadata["instagram_business_account_id"] == @social_destination.external_id &&
      @configuration.fetch(:supported_destination_account_types).include?(metadata["instagram_account_type"])
  end

  def render_file_ready?
    @render_version.ready? && @render_version.file.attached?
  end

  def upload_started_or_complete?
    @checkpoint["upload_started"] == true || @checkpoint["upload_complete"] == true
  end

  def step_check_publishing_limit
    response = instagram_client.instagram_content_publishing_limit(
      instagram_user_id: @social_destination.external_id,
      page_access_token: @social_destination.access_token
    )
    quota = Array(response["data"]).first.to_h
    quota_usage = quota["quota_usage"]
    quota_total = quota.dig("config", "quota_total")
    unless quota_usage.is_a?(Numeric) && quota_total.is_a?(Numeric)
      return step_mark_failed(safe_error_code(:publishing_limit_unavailable)) if @checkpoint["upload_complete"] == true

      return step_record_pre_send_failure(:publishing_limit_unavailable)
    end
    return true if quota_usage < quota_total
    return step_mark_failed(safe_error_code(:publishing_limit_reached)) if @checkpoint["upload_complete"] == true

    step_record_pre_send_failure(:publishing_limit_reached)
  end

  def step_start_container
    return false unless step_start_outbound_attempt(purpose: :container_upload)

    response = instagram_client.start_instagram_reel_upload(
      instagram_user_id: @social_destination.external_id,
      page_access_token: @social_destination.access_token,
      caption: publication.caption
    )
    return step_mark_outcome_unknown(safe_error_code(:invalid_container_response)) unless response.is_a?(Hash)

    creation_id = response["id"].presence
    upload_url = response["uri"].presence
    return step_mark_outcome_unknown(safe_error_code(:invalid_container_response)) unless creation_id && upload_url

    @creation_id = creation_id
    @upload_url = upload_url
    return false unless step_save_checkpoint(
      "creation_id" => creation_id,
      "upload_url" => upload_url,
      "upload_started" => false,
      "upload_complete" => false,
      "status_poll_attempts" => 0
    )

    publication.update!(provider_reference: provider_reference)
    step_record_audit_event(:container_created, details: { creation_id: })
    true
  end

  def step_upload_video
    return false unless step_save_checkpoint("upload_started" => true)

    response = @render_version.file.open do |file|
      instagram_client.upload_instagram_reel(
        upload_url: @checkpoint.fetch("upload_url"),
        page_access_token: @social_destination.access_token,
        file:,
        file_size: @render_version.file.byte_size
      )
    end
    return step_mark_outcome_unknown(safe_error_code(:upload_not_confirmed)) unless response.is_a?(Hash) && response["success"] == true

    step_confirm_uploaded_attempt
  end

  def step_check_container_status
    response = instagram_client.instagram_reel_status(
      creation_id: @checkpoint.fetch("creation_id"),
      page_access_token: @social_destination.access_token
    )
    return step_mark_outcome_unknown(safe_error_code(:container_status_unknown)) unless response.is_a?(Hash)

    status = response["status_code"]
    return step_mark_published if status == @configuration.fetch(:instagram_container_statuses).fetch(:published)
    return step_mark_failed(safe_error_code(:publish_failed)) if @configuration.fetch(:instagram_container_statuses).fetch(:failed).include?(status)
    return step_schedule_status_poll if @configuration.fetch(:instagram_container_statuses).fetch(:processing).include?(status)
    return step_reconcile_published_container if status == @configuration.fetch(:instagram_container_statuses).fetch(:ready) && @checkpoint["media_publish_started"] == true
    if status == @configuration.fetch(:instagram_container_statuses).fetch(:ready)
      return false unless step_confirm_uploaded_attempt if @checkpoint["upload_complete"] != true

      return step_publish_finished_container
    end

    step_mark_outcome_unknown(safe_error_code(:container_status_unknown))
  end

  def step_publish_finished_container
    return false unless step_check_publishing_limit
    return false unless step_start_outbound_attempt(purpose: :media_publish)
    return false unless step_save_checkpoint("media_publish_started" => true)

    step_record_audit_event(:media_publish_started, details: { creation_id: @checkpoint.fetch("creation_id") })
    response = instagram_client.publish_instagram_reel(
      instagram_user_id: @social_destination.external_id,
      page_access_token: @social_destination.access_token,
      creation_id: @checkpoint.fetch("creation_id")
    )
    media_id = response.is_a?(Hash) ? response["id"].presence : nil
    return step_mark_outcome_unknown(safe_error_code(:publish_outcome_unknown)) unless media_id

    @media_id = media_id
    return false unless step_save_checkpoint("media_id" => media_id)

    step_load_permalink
    step_mark_published
  end

  def step_load_permalink
    response = instagram_client.instagram_media(
      media_id: @media_id,
      page_access_token: @social_destination.access_token
    )
    return unless response.is_a?(Hash) && response["id"].to_s == @media_id.to_s

    @permalink = response["permalink"] if instagram_permalink?(response["permalink"])
  rescue Meta::Client::Error
    nil
  end

  def instagram_permalink?(value)
    uri = URI(value.to_s)
    @configuration.fetch(:permalink_hosts).include?(uri.host&.downcase) && uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def step_reconcile_unknown
    return false unless step_claim_workflow
    return step_keep_outcome_unknown unless @checkpoint["creation_id"].present?

    response = instagram_client.instagram_reel_status(
      creation_id: @checkpoint.fetch("creation_id"),
      page_access_token: @social_destination.access_token
    )
    return step_keep_outcome_unknown unless response.is_a?(Hash)

    status = response["status_code"]
    return step_mark_published_from_reconciliation if status == @configuration.fetch(:instagram_container_statuses).fetch(:published)
    return step_mark_failed(safe_error_code(:publish_failed)) if @configuration.fetch(:instagram_container_statuses).fetch(:failed).include?(status)
    return step_keep_outcome_unknown if @checkpoint["media_publish_started"] == true
    return step_reconcile_upload(status) if status == @configuration.fetch(:instagram_container_statuses).fetch(:ready)

    step_keep_outcome_unknown
  rescue Meta::Client::Error
    step_keep_outcome_unknown
  end

  def step_reconcile_upload(status)
    return step_keep_outcome_unknown unless status == @configuration.fetch(:instagram_container_statuses).fetch(:ready)
    return false unless step_save_checkpoint("upload_complete" => true)

    step_with_live_lease do
      outbound_attempt.update!(status: :confirmed, safe_error_code: nil, provider_reference:)
      publication.update!(status: :processing, safe_error_code: nil, provider_reference:)
      workflow_run.update!(status: :queued, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:upload_confirmed),
        stage: publish_stage,
        details: { reconciled: true }
      )
      step_succeed!
    end
    return false unless success?

    Publications::PublishJob.perform_later(workflow_run.id)
    true
  end

  def step_reconcile_published_container
    step_mark_outcome_unknown(safe_error_code(:publish_outcome_unknown))
  end

  def step_mark_published_from_reconciliation
    @media_id = @checkpoint["media_id"]
    step_load_permalink if @media_id.present?
    step_mark_published
  end

  def step_confirm_uploaded_attempt
    return true if @checkpoint["upload_complete"] == true && outbound_attempt&.confirmed?
    return false unless step_save_checkpoint("upload_complete" => true)

    step_with_live_lease do
      now = Time.current
      outbound_attempt.update!(status: :confirmed, sender_stopped_at: now, safe_error_code: nil, provider_reference:)
      publication.update!(status: :processing, safe_error_code: nil, provider_reference:)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:upload_confirmed),
        stage: publish_stage
      )
      step_succeed!
    end
  end

  def step_mark_published
    @media_id ||= @checkpoint["media_id"]
    step_with_live_lease do
      now = Time.current
      publication.update!(
        status: :published,
        platform_post_id: @media_id,
        permalink: @permalink,
        published_at: now,
        provider_reference: provider_reference,
        safe_error_code: nil
      )
      outbound_attempt.update!(status: :confirmed, sender_stopped_at: now, safe_error_code: nil, provider_reference:) if outbound_attempt
      workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:published),
        stage: publish_stage,
        details: { creation_id: @checkpoint["creation_id"], media_id: @media_id, permalink: @permalink }.compact
      )
      step_succeed!
    end
  end

  def step_schedule_status_poll
    attempts = @checkpoint.fetch("status_poll_attempts", 0).to_i + 1
    return step_mark_outcome_unknown(safe_error_code(:container_status_unknown)) if attempts >= max_status_poll_attempts
    return false unless step_save_checkpoint("status_poll_attempts" => attempts)

    step_with_live_lease do
      publication.update!(status: :processing, provider_reference:)
      workflow_run.update!(status: :queued, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:processing),
        stage: publish_stage,
        details: { status_poll_attempts: attempts }
      )
      step_succeed!
    end
    return false unless success?

    Publications::PublishJob.set(wait: status_poll_interval).perform_later(workflow_run.id)
    true
  end

  def step_start_outbound_attempt(purpose:)
    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: workflow_run.id,
      worker_id:,
      fencing_token: workflow_run.fencing_token,
      stage: publish_stage,
      request_timeout_at: Time.current + request_timeout,
      idempotency_key: "instagram-publication-#{publication.id}-#{purpose}"
    )
    return step_fail!(start_service.errors.full_messages.to_sentence) unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    true
  end

  def step_claim_workflow
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: workflow_run.id,
      worker_id:,
      lease_duration: request_timeout + 30.seconds
    )
    return step_fail!(claim_service.errors.full_messages.to_sentence) unless claim_service.call

    @workflow_run = claim_service.workflow_run
    true
  end

  def step_mark_failed(error_code)
    step_with_live_lease do
      now = Time.current
      if outbound_attempt&.submitting?
        outbound_attempt.update!(status: :failed, sender_stopped_at: now, safe_error_code: error_code, provider_reference:)
      end
      publication.update!(status: :failed, safe_error_code: error_code, provider_reference:)
      workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:failed),
        stage: publish_stage,
        details: { safe_error_code: error_code }
      )
      step_fail!("Instagram không hoàn tất bài đăng. Mã lỗi an toàn: #{error_code}.")
    end
  end

  def step_mark_outcome_unknown(error_code)
    return step_record_pre_send_failure(:publishing_limit_unavailable) unless outbound_attempt

    step_with_live_lease do
      now = Time.current
      outbound_attempt.update!(status: :outcome_unknown, sender_stopped_at: now, safe_error_code: error_code, provider_reference:)
      publication.update!(status: :outcome_unknown, provider_reference:, safe_error_code: error_code)
      workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:outcome_unknown),
        stage: publish_stage,
        details: { safe_error_code: error_code }
      )
      step_fail!("Instagram chưa xác nhận được kết quả đăng; cần đối soát trước khi thử lại.")
    end
  end

  def step_keep_outcome_unknown
    step_with_live_lease do
      workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      step_fail!("Instagram vẫn chưa xác nhận kết quả; không gửi lại yêu cầu đăng.")
    end
  end

  def step_with_live_lease
    WorkflowRun.transaction do
      current_workflow_run = WorkflowRun.lock.find_by(id: @workflow_run_id)
      if step_current_lease?(current_workflow_run)
        @workflow_run = current_workflow_run
        yield
      else
        step_fail!("Workflow đang được worker khác giữ hoặc chưa đến lượt xử lý.")
      end
    end
  end

  def step_current_lease?(current_workflow_run)
    current_workflow_run&.running? && current_workflow_run.worker_id == worker_id &&
      current_workflow_run.fencing_token == workflow_run.fencing_token &&
      current_workflow_run.lease_expires_at.present? && current_workflow_run.lease_expires_at > Time.current
  end

  def step_save_checkpoint(values)
    checkpoint_service = WorkflowRuns::CheckpointService.new(
      workflow_run_id: workflow_run.id,
      worker_id:,
      fencing_token: workflow_run.fencing_token,
      stage: publish_stage,
      checkpoint: values
    )
    return step_fail!(checkpoint_service.errors.full_messages.to_sentence) unless checkpoint_service.call

    @workflow_run = checkpoint_service.workflow_run
    @checkpoint = @workflow_run.checkpoint.to_h.stringify_keys
    true
  end

  def step_record_audit_event(key, details:)
    workflow_run.workflow_audit_events.create!(
      outbound_attempt:,
      event_type: audit_event(key),
      stage: publish_stage,
      details:
    )
  end

  def step_handle_client_error(error)
    error_code = error.code
    return step_record_pre_send_failure(:publishing_limit_unavailable) unless outbound_attempt
    return step_mark_outcome_unknown(error_code) if ambiguous_error?(error_code)

    step_mark_failed(error_code)
  end

  def ambiguous_error?(error_code)
    @configuration.fetch(:instagram_ambiguous_error_codes).include?(error_code) ||
      error_code.start_with?(@configuration.fetch(:instagram_ambiguous_http_error_prefix))
  end

  def step_record_pre_send_failure(error_key)
    error_code = safe_error_code(error_key)
    publication.update!(safe_error_code: error_code)
    step_fail!(pre_send_failure_message(error_key))
  end

  def safe_error_code(key)
    @configuration.fetch(:instagram_safe_error_codes).fetch(key)
  end

  def pre_send_failure_message(error_key)
    case error_key
    when :business_account_required
      "MVP chỉ hỗ trợ tài khoản Instagram Business có Page liên kết."
    when :publishing_limit_reached
      "Instagram đã báo tài khoản này chạm giới hạn đăng hiện hành."
    when :publishing_limit_unavailable
      "Chưa thể kiểm tra giới hạn đăng Instagram hiện tại."
    when :source_not_ready
      "Render version chưa sẵn sàng hoặc thiếu file video."
    else
      "Không thể xác minh điều kiện đăng Instagram hiện tại."
    end
  end

  def provider_reference
    {
      provider: "instagram",
      creation_id: @checkpoint["creation_id"],
      media_id: @media_id || @checkpoint["media_id"]
    }.compact
  end

  def instagram_client
    @instagram_client ||= Meta::Client.new(provider: :instagram)
  end

  def publish_stage
    @configuration.fetch(:publish_stage)
  end

  def audit_event(key)
    @configuration.fetch(:instagram_audit_events).fetch(key)
  end

  def worker_id
    @worker_id ||= "#{@configuration.fetch(:worker_id_prefix)}-#{SecureRandom.uuid}"
  end

  def client_error_code(key)
    @configuration.fetch(:instagram_client_error_codes).fetch(key)
  end

  def request_timeout
    @configuration.fetch(:upload_timeout_seconds).to_i +
      (@configuration.fetch(:read_timeout_seconds).to_i * 3) +
      (@configuration.fetch(:open_timeout_seconds).to_i * 4)
  end

  def status_poll_interval
    @configuration.fetch(:instagram_status_poll_interval_seconds).to_i.seconds
  end

  def max_status_poll_attempts
    @configuration.fetch(:instagram_max_status_poll_attempts).to_i
  end
end
