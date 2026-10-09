class Publications::YoutubePublisher < ApplicationService
  attr_reader :publication, :workflow_run, :outbound_attempt

  # Initializes a YouTube publisher for one persisted Publication workflow.
  #
  # @param workflow_run_id [Integer] the queued YouTube publication workflow
  # @return [Publications::YoutubePublisher] the configured service
  def initialize(workflow_run_id:)
    @workflow_run_id = workflow_run_id
    @configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:publisher)
    super()
  end

  # Resumes or publishes a YouTube video and confirms its processed privacy state.
  #
  # @return [Boolean] whether the workflow completed or queued a status check
  def call
    return false unless step_load_workflow
    return step_succeed_for_published_publication if publication.published?
    return false unless step_validate_publication
    return false unless step_validate_consent
    return false if step_block_unresolved_attempt
    return false unless step_load_access_token
    return false unless step_claim_workflow
    return false unless step_start_outbound_attempt
    return false unless step_create_upload_session
    return false unless step_upload_video

    step_check_video_status
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  rescue Youtube::Client::Error => error
    step_handle_client_error(error)
  end

  private

  def step_load_workflow
    @workflow_run = WorkflowRun.find_by(id: @workflow_run_id)
    return step_fail!("Không tìm thấy workflow đăng YouTube.") unless workflow_run
    return step_fail!("Workflow không phải thao tác đăng YouTube.") unless publish_workflow?

    @publication = workflow_run.workflowable
    return step_fail!("Không tìm thấy Publication cần đăng.") unless publication.is_a?(Publication)

    @social_destination = publication.social_destination
    @social_connection = @social_destination.social_connection
    @render_version = publication.render_version
    @checkpoint = workflow_run.checkpoint.to_h.stringify_keys
    @outbound_attempt = workflow_run.outbound_attempts.for_stage(publish_stage).first
    @consent_snapshot = publication.consent_snapshot.to_h.stringify_keys
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
    return step_record_pre_send_failure(:invalid_publication) unless publication.approved? ||
      publication.uploading? || publication.processing?
    return step_record_pre_send_failure(:invalid_destination) unless youtube_destination_ready?
    return step_record_pre_send_failure(:invalid_render) unless render_file_ready?

    true
  end

  def youtube_destination_ready?
    @social_destination.provider == provider_key && @social_connection.connected? && @social_destination.connected?
  end

  def render_file_ready?
    @render_version.ready? && @render_version.file.attached?
  end

  def step_validate_consent
    return step_record_pre_send_failure(:missing_upload_terms_confirmation) unless upload_terms_confirmed?
    return step_record_pre_send_failure(:consent_account_mismatch) unless consent_account_matches?
    return step_record_pre_send_failure(:consent_channel_mismatch) unless consent_channel_matches?
    return step_record_pre_send_failure(:consent_render_mismatch) unless consent_render_matches?
    return step_record_pre_send_failure(:consent_publication_mismatch) unless consent_publication_matches?
    return step_record_pre_send_failure(:invalid_privacy_choice) unless privacy_status_allowed?
    return step_record_pre_send_failure(:missing_made_for_kids_disclosure) unless boolean_consent?("self_declared_made_for_kids")
    return step_record_pre_send_failure(:missing_synthetic_media_disclosure) unless boolean_consent?("contains_synthetic_media")

    true
  end

  def upload_terms_confirmed?
    @consent_snapshot["upload_terms_confirmed"] == true &&
      @consent_snapshot["confirmed_at"].present?
  end

  def consent_account_matches?
    @consent_snapshot["youtube_account_id"].to_s == @social_connection.external_user_id.to_s
  end

  def consent_channel_matches?
    @consent_snapshot["youtube_channel_id"].to_s == @social_destination.external_id.to_s
  end

  def consent_render_matches?
    @consent_snapshot["render_version_id"].to_s == @render_version.id.to_s
  end

  def consent_publication_matches?
    @consent_snapshot["publication_id"].to_s == publication.id.to_s
  end

  def privacy_status_allowed?
    @configuration.fetch(:privacy_statuses).include?(@consent_snapshot["privacy_status"])
  end

  def boolean_consent?(key)
    [ true, false ].include?(@consent_snapshot[key])
  end

  def step_block_unresolved_attempt
    return false unless outbound_attempt
    return false if outbound_attempt.submitting? && @checkpoint["upload_session_uri"].present?
    return false if outbound_attempt.confirmed? && completed_upload_checkpoint?

    step_record_pre_send_failure(:unresolved_attempt)
  end

  def completed_upload_checkpoint?
    @checkpoint["upload_complete"] == true && @checkpoint["video_id"].present?
  end

  def step_load_access_token
    token_service = SocialConnections::Youtube::AccessTokenService.new(
      social_destination_id: @social_destination.id
    )
    return step_fail!(token_service.errors.full_messages.to_sentence) unless token_service.call

    @access_token = token_service.access_token
    @social_destination.reload
    @social_connection = @social_destination.social_connection
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

  def step_start_outbound_attempt
    return true if outbound_attempt

    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: workflow_run.id,
      worker_id:,
      fencing_token: workflow_run.fencing_token,
      stage: publish_stage,
      request_timeout_at: Time.current + request_timeout,
      idempotency_key: "youtube-publication-#{publication.id}-insert"
    )
    return step_fail!(start_service.errors.full_messages.to_sentence) unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    publication.update!(status: :uploading, safe_error_code: nil)
    true
  end

  def step_create_upload_session
    return true if @checkpoint["upload_session_uri"].present? || completed_upload_checkpoint?
    return step_fail!("Không tìm thấy file video để đăng YouTube.") unless render_file_ready?

    session_uri = youtube_client.start_resumable_upload(
      access_token: @access_token,
      metadata: upload_metadata,
      file_size: @render_version.file.byte_size,
      content_type: @render_version.file.content_type
    )
    return step_mark_outcome_unknown(:invalid_upload_response) if session_uri.blank?

    saved = step_save_checkpoint(
      "upload_session_uri" => session_uri,
      "uploaded_bytes" => 0,
      "upload_complete" => false
    )
    @session_started_this_call = true if saved
    saved
  end

  def upload_metadata
    {
      "snippet" => {
        "title" => publication.caption.to_s.truncate(@configuration.fetch(:title_max_characters).to_i, omission: ""),
        "description" => publication.caption.to_s.truncate(@configuration.fetch(:description_max_characters).to_i, omission: ""),
        "tags" => []
      },
      "status" => {
        "privacyStatus" => @consent_snapshot.fetch("privacy_status"),
        "selfDeclaredMadeForKids" => @consent_snapshot.fetch("self_declared_made_for_kids"),
        "containsSyntheticMedia" => @consent_snapshot.fetch("contains_synthetic_media")
      }
    }
  end

  def step_upload_video
    return true if completed_upload_checkpoint?

    offset = @checkpoint.fetch("uploaded_bytes", 0).to_i
    if resumed_upload?
      status = youtube_client.upload_status(
        access_token: @access_token,
        session_uri: @checkpoint.fetch("upload_session_uri"),
        file_size: @render_version.file.byte_size
      )
      return false unless step_accept_upload_status(status)

      offset = status.fetch(:uploaded_bytes).to_i
      return step_confirm_upload(status.fetch(:video_id)) if status[:video_id].present?
    end

    step_send_remaining_bytes(offset)
  end

  def resumed_upload?
    !@session_started_this_call && outbound_attempt&.persisted? && @checkpoint["upload_session_uri"].present? &&
      outbound_attempt.request_started_at.present?
  end

  def step_accept_upload_status(status)
    return step_mark_outcome_unknown(:invalid_upload_response) unless status.is_a?(Hash)
    return step_save_checkpoint("uploaded_bytes" => status.fetch(:uploaded_bytes).to_i) if status[:video_id].blank?

    true
  end

  def step_send_remaining_bytes(offset)
    file_size = @render_version.file.byte_size
    loop do
      return step_mark_outcome_unknown(:invalid_upload_response) unless offset.between?(0, file_size)
      return step_confirm_upload(@checkpoint["video_id"]) if offset == file_size && @checkpoint["video_id"].present?
      return step_mark_outcome_unknown(:invalid_upload_response) if offset == file_size

      result = nil
      @render_version.file.open do |file|
        result = youtube_client.upload_remaining(
          access_token: @access_token,
          session_uri: @checkpoint.fetch("upload_session_uri"),
          file:,
          file_size:,
          offset:,
          content_type: @render_version.file.content_type
        )
      end
      return step_mark_outcome_unknown(:invalid_upload_response) unless result.is_a?(Hash)
      return step_confirm_upload(result.fetch(:video_id)) if result[:video_id].present?

      next_offset = result.fetch(:uploaded_bytes).to_i
      return step_mark_outcome_unknown(:invalid_upload_response) unless next_offset > offset && next_offset <= file_size
      return false unless step_save_checkpoint("uploaded_bytes" => next_offset)

      offset = next_offset
    end
  end

  def step_confirm_upload(video_id)
    return step_mark_outcome_unknown(:invalid_upload_response) if video_id.blank?
    return false unless step_save_checkpoint(
      "uploaded_bytes" => @render_version.file.byte_size,
      "video_id" => video_id,
      "upload_complete" => true
    )

    step_with_live_lease do
      now = Time.current
      @outbound_attempt.update!(status: :confirmed, sender_stopped_at: now, provider_reference: provider_reference)
      publication.update!(status: :processing, provider_reference: provider_reference)
      @workflow_run.workflow_audit_events.create!(
        outbound_attempt: @outbound_attempt,
        event_type: "youtube_upload_confirmed",
        stage: publish_stage,
        details: { video_id: }
      )
      step_succeed!
    end
  end

  def step_check_video_status
    response = youtube_client.video_status(access_token: @access_token, video_id: @checkpoint.fetch("video_id"))
    return step_mark_outcome_unknown(:processing_unknown) unless response.is_a?(Hash)
    return step_mark_outcome_unknown(:processing_unknown) unless response["id"].to_s == @checkpoint.fetch("video_id").to_s
    return step_mark_outcome_unknown(:processing_unknown) unless response.dig("snippet", "channelId").to_s == @social_destination.external_id.to_s

    processing_status = response.dig("processingDetails", "processingStatus")
    upload_status = response.dig("status", "uploadStatus")
    provider_statuses = @configuration.fetch(:provider_statuses)
    return step_mark_failed(:processing_failed) if provider_statuses.fetch(:processing).fetch(:failed).include?(processing_status)
    return step_mark_outcome_unknown(:processing_unknown) unless processing_status.present? && upload_status.present?
    return step_schedule_status_check if provider_statuses.fetch(:processing).fetch(:in_progress).include?(processing_status) ||
      upload_status == provider_statuses.fetch(:upload).fetch(:in_progress)
    return step_mark_failed(:processing_failed) unless processing_status == provider_statuses.fetch(:processing).fetch(:succeeded)
    return step_mark_failed(:processing_failed) unless upload_status == provider_statuses.fetch(:upload).fetch(:completed)
    return step_mark_failed(:processing_failed) unless response.dig("status", "privacyStatus") == @consent_snapshot.fetch("privacy_status")

    step_mark_published(response)
  end

  def step_schedule_status_check
    attempts = @checkpoint.fetch("status_poll_attempts", 0).to_i + 1
    return step_mark_outcome_unknown(:processing_unknown) if attempts >= @configuration.fetch(:status_poll_max_attempts).to_i
    return false unless step_save_checkpoint("status_poll_attempts" => attempts)

    step_with_live_lease do
      publication.update!(status: :processing, provider_reference: provider_reference)
      @workflow_run.update!(status: :queued, worker_id: nil, lease_expires_at: nil)
      step_succeed!
    end
    return false unless success?

    Publications::PublishJob.set(wait: @configuration.fetch(:status_poll_interval_seconds).seconds)
      .perform_later(@workflow_run.id)
    true
  end

  def step_mark_published(response)
    video_id = response.fetch("id")
    privacy_status = response.dig("status", "privacyStatus")
    permalink = "https://www.youtube.com/watch?v=#{ERB::Util.url_encode(video_id)}"
    step_with_live_lease do
      now = Time.current
      publication.update!(
        status: :published,
        platform_post_id: video_id,
        permalink:,
        published_at: now,
        provider_reference: { provider: provider_key, video_id:, privacy_status: },
        safe_error_code: nil
      )
      @workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        outbound_attempt: @outbound_attempt,
        event_type: "youtube_video_published",
        stage: publish_stage,
        details: { video_id:, privacy_status: }
      )
      step_succeed!
    end
    success?
  end

  def step_mark_failed(error_key)
    step_with_live_lease do
      error_code = safe_error_code(error_key)
      now = Time.current
      @outbound_attempt&.update!(status: :failed, sender_stopped_at: now, safe_error_code: error_code)
      publication.update!(status: :failed, safe_error_code: error_code, provider_reference: provider_reference)
      @workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      step_fail!("YouTube không hoàn tất video. Mã lỗi an toàn: #{error_code}.")
    end
  end

  def step_mark_outcome_unknown(error_key)
    step_with_live_lease do
      error_code = safe_error_code(error_key)
      now = Time.current
      @outbound_attempt&.update!(status: :outcome_unknown, sender_stopped_at: now, safe_error_code: error_code)
      publication.update!(
        status: :outcome_unknown,
        provider_reference: provider_reference,
        safe_error_code: error_code
      )
      @workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      step_fail!("YouTube chưa xác nhận được kết quả upload; cần đối soát trước khi thử lại.")
    end
  end

  def step_record_pre_send_failure(error_key)
    error_code = safe_error_code(error_key)
    publication.update!(safe_error_code: error_code)
    step_fail!("Không thể bắt đầu đăng YouTube. Mã lỗi an toàn: #{error_code}.")
  end

  def step_handle_client_error(error)
    return step_record_pre_send_failure(:upload_failed) unless outbound_attempt
    return step_mark_outcome_unknown(:network_request_failed) if error.code == "network_request_failed"
    return step_mark_outcome_unknown(:invalid_upload_response) if error.code.in?(%w[invalid_json_response missing_upload_session])
    return step_mark_failed(:quota_exhausted) if error.code == "quota_exhausted"
    return step_mark_failed(:upload_limit_exhausted) if error.code == "upload_limit_exhausted"

    step_mark_failed(:upload_failed)
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

  def provider_reference
    {
      provider: provider_key,
      video_id: @checkpoint["video_id"],
      privacy_status: @consent_snapshot["privacy_status"]
    }.compact
  end

  def safe_error_code(key)
    @configuration.fetch(:safe_error_codes).fetch(key)
  end

  def youtube_client
    @youtube_client ||= Youtube::Client.new
  end

  def provider_key
    @configuration.fetch(:provider_key).to_s
  end

  def publish_stage
    @configuration.fetch(:publish_stage)
  end

  def worker_id
    @worker_id ||= "#{@configuration.fetch(:worker_id_prefix)}-#{SecureRandom.uuid}"
  end

  def request_timeout
    @configuration.fetch(:request_timeout_seconds).seconds
  end
end
