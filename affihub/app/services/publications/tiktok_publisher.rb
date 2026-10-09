class Publications::TikTokPublisher < ApplicationService
  attr_reader :publication, :workflow_run, :outbound_attempt

  # Initializes the TikTok publisher for a persisted Publication workflow.
  #
  # @param workflow_run_id [Integer] the queued TikTok publication workflow
  # @return [Publications::TikTokPublisher] the configured service
  def initialize(workflow_run_id:)
    @workflow_run_id = workflow_run_id
    @configuration = SocialConnections::ProviderConfiguration.for(:tiktok)
    super()
  end

  # Publishes a TikTok video or polls the status of an acknowledged publish ID.
  #
  # @return [Boolean] whether the workflow completed or queued a status check
  def call
    return false unless step_load_workflow
    return step_succeed_for_published_publication if publication.published?
    return false unless step_validate_publication
    return false if step_block_unresolved_attempt
    return step_poll_existing_publish if status_check_ready?
    return false unless step_check_app_local_cap
    return false unless step_load_access_token
    return false unless step_load_creator_info
    return false unless step_validate_creator_consent
    return false unless step_claim_workflow
    return false unless step_start_outbound_attempt
    return false unless step_start_video_publish
    return false unless step_upload_video
    return false unless step_confirm_upload

    step_check_publish_status
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  rescue TikTok::Client::Error => error
    step_handle_client_error(error)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse
    step_handle_client_error(TikTok::Client::Error.new(client_error_code(:network_request_failed)))
  end

  private

  def step_load_workflow
    @workflow_run = WorkflowRun.find_by(id: @workflow_run_id)
    return step_fail!("Không tìm thấy workflow đăng TikTok.") unless workflow_run
    return step_fail!("Workflow không phải thao tác đăng TikTok.") unless publish_workflow?

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
    return step_fail!("Chỉ hỗ trợ tài khoản TikTok đã kết nối.") unless tiktok_destination_ready?
    return step_fail!("Render version chưa sẵn sàng hoặc thiếu file video.") unless render_file_ready?
    return step_record_pre_send_failure(:caption_too_long) unless caption_within_provider_limit?

    true
  end

  def publication_ready?
    publication.approved? || publication.uploading? || publication.processing? ||
      publication.manual_outcome_not_occurred?
  end

  def tiktok_destination_ready?
    @social_destination.provider == provider_key && @social_connection.connected? &&
      @social_destination.connected?
  end

  def render_file_ready?
    @render_version.ready? && @render_version.file.attached?
  end

  def caption_within_provider_limit?
    caption_length = publication.caption.to_s.encode("UTF-16LE").bytesize / 2
    caption_length <= @configuration.fetch(:title_max_utf16_units).to_i
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    false
  end

  def step_block_unresolved_attempt
    return false unless outbound_attempt
    return step_fail!("Outbound attempt cần được đối soát trước khi gửi lại.") if outbound_attempt.submitting? || outbound_attempt.outcome_unknown?
    return false if outbound_attempt.confirmed? && status_check_ready?
    return false unless outbound_attempt.confirmed?

    step_fail!("Outbound attempt cần được đối soát trước khi gửi lại.")
  end

  def status_check_ready?
    outbound_attempt&.confirmed? && @checkpoint["upload_complete"] == true && @checkpoint["publish_id"].present?
  end

  def step_poll_existing_publish
    return false unless step_load_access_token
    return false unless step_claim_workflow

    step_check_publish_status
  end

  def step_check_app_local_cap
    return true if step_creator_slot_available_under_lock?

    step_record_pre_send_failure(:app_local_cap_reached)
  end

  def step_creator_slot_available_under_lock?
    SocialConnection.transaction do
      step_lock_app_cap_connection
      @app_cap_lock_connection.present? && step_creator_slot_available?
    end
  end

  def step_lock_app_cap_connection
    @app_cap_lock_connection = SocialConnection.where(provider: provider_key).order(:id).lock.first
  end

  def step_creator_slot_available?
    recent_creator_ids = SocialConnection.with_publish_attempt_since(
      provider: provider_key,
      operation: @configuration.fetch(:publication_operation),
      stage: publish_stage,
      since: cap_window_start
    ).pluck(:id)

    recent_creator_ids.include?(@social_connection.id) ||
      recent_creator_ids.length < @configuration.fetch(:max_distinct_creators_per_24_hours).to_i
  end

  def cap_window_start
    Time.current - @configuration.fetch(:max_distinct_creators_window_seconds).to_i.seconds
  end

  def step_load_access_token
    token_service = SocialConnections::TikTok::AccessTokenService.new(
      social_destination_id: @social_destination.id
    )
    return step_fail!(token_service.errors.full_messages.to_sentence) unless token_service.call

    @access_token = token_service.access_token
    @social_destination.reload
    @social_connection = @social_destination.social_connection
    true
  end

  def step_load_creator_info
    response = tiktok_client.creator_info(access_token: @access_token)
    error_code = provider_error_code(response)
    return step_record_provider_cap(error_code) if provider_cap_error?(error_code)
    return step_record_pre_send_failure(:creator_info_unavailable) unless provider_success?(response)

    @creator_info = response.fetch("data", {}).to_h
    true
  end

  def step_record_provider_cap(error_code)
    cap_key = error_code == @configuration.fetch(:provider_cap_errors).fetch(:creator) ? :creator_cap_reached : :provider_app_cap_reached
    step_record_pre_send_failure(cap_key)
  end

  def step_validate_creator_consent
    @consent_snapshot = publication.consent_snapshot.to_h.stringify_keys
    return step_record_pre_send_failure(:missing_privacy_choice) if @consent_snapshot["privacy_level"].blank?
    return step_record_pre_send_failure(:privacy_not_allowed) unless privacy_allowed?
    return step_record_pre_send_failure(:privacy_unavailable) unless creator_allows_privacy?
    return step_record_pre_send_failure(:private_account_not_confirmed) unless private_account_confirmed?
    return step_record_pre_send_failure(:music_usage_not_confirmed) unless music_usage_confirmed?
    return step_record_pre_send_failure(:ai_disclosure_not_confirmed) unless ai_disclosure_confirmed?
    return step_record_pre_send_failure(:interaction_disabled) if disabled_interaction_selected?
    return step_record_pre_send_failure(:branded_content_self_only) if branded_content_with_self_only?

    true
  end

  def privacy_allowed?
    return true if @configuration.fetch(:content_posting_audited)

    @configuration.fetch(:unaudited_allowed_privacy_levels).include?(@consent_snapshot.fetch("privacy_level"))
  end

  def creator_allows_privacy?
    Array(@creator_info["privacy_level_options"]).include?(@consent_snapshot.fetch("privacy_level"))
  end

  def private_account_confirmed?
    return true unless @configuration.fetch(:unaudited_requires_private_account)

    @configuration.fetch(:content_posting_audited) || @consent_snapshot["creator_account_private"] == true
  end

  def music_usage_confirmed?
    !@configuration.fetch(:require_music_usage_confirmation) || @consent_snapshot["music_usage_confirmed"] == true
  end

  def ai_disclosure_confirmed?
    return true unless @configuration.fetch(:require_aigc_disclosure_confirmation)

    @consent_snapshot.key?("is_aigc") && [ true, false ].include?(@consent_snapshot["is_aigc"])
  end

  def disabled_interaction_selected?
    (@creator_info["comment_disabled"] == true && @consent_snapshot["allow_comment"] == true) ||
      (@creator_info["duet_disabled"] == true && @consent_snapshot["allow_duet"] == true) ||
      (@creator_info["stitch_disabled"] == true && @consent_snapshot["allow_stitch"] == true)
  end

  def branded_content_with_self_only?
    @consent_snapshot.fetch("privacy_level") == "SELF_ONLY" &&
      @consent_snapshot["brand_content_toggle"] == true
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
    started = SocialConnection.transaction do
      step_lock_app_cap_connection

      if @app_cap_lock_connection.blank?
        step_record_pre_send_failure(:app_local_cap_reached)
      elsif !step_creator_slot_available?
        step_record_pre_send_failure(:app_local_cap_reached)
      else
        step_create_outbound_attempt
      end
    end
    started == true
  end

  def step_create_outbound_attempt
    start_service = OutboundAttempts::StartService.new(
      workflow_run_id: workflow_run.id,
      worker_id:,
      fencing_token: workflow_run.fencing_token,
      stage: publish_stage,
      request_timeout_at: Time.current + request_timeout,
      idempotency_key: "#{provider_key}-publication-#{publication.id}-publish"
    )
    return step_fail!("Không thể ghi nhận outbound attempt trước khi gửi TikTok.") unless start_service.call

    @outbound_attempt = start_service.outbound_attempt
    publication.update!(status: :uploading, safe_error_code: nil)
    true
  end

  def step_start_video_publish
    @source_info = tiktok_client.file_upload_source_info(file_size: @render_version.file.byte_size)
    response = tiktok_client.init_video_publish(
      access_token: @access_token,
      post_info: post_info,
      source_info: @source_info
    )
    return step_mark_outcome_unknown(safe_error_code(:invalid_publish_response)) unless response.is_a?(Hash)
    return false unless step_handle_provider_response(response)

    response_data = response.fetch("data", {}).to_h
    @publish_id = response_data["publish_id"].presence
    @upload_url = response_data["upload_url"].presence
    return step_mark_outcome_unknown(safe_error_code(:invalid_publish_response)) unless @publish_id && @upload_url

    return false unless step_save_checkpoint(
      "publish_id" => @publish_id,
      "upload_url" => @upload_url,
      "upload_offset" => 0
    )

    publication.update!(provider_reference: provider_reference)
    true
  end

  def post_info
    {
      "title" => publication.caption,
      "privacy_level" => @consent_snapshot.fetch("privacy_level"),
      "disable_comment" => @consent_snapshot["allow_comment"] != true,
      "disable_duet" => @consent_snapshot["allow_duet"] != true,
      "disable_stitch" => @consent_snapshot["allow_stitch"] != true,
      "brand_organic_toggle" => @consent_snapshot["brand_organic_toggle"] == true,
      "brand_content_toggle" => @consent_snapshot["brand_content_toggle"] == true,
      "is_aigc" => @consent_snapshot["is_aigc"] == true
    }
  end

  def step_upload_video
    uploaded_bytes = nil
    @render_version.file.open do |file|
      response = tiktok_client.upload_file(
        upload_url: @upload_url,
        file:,
        file_size: @render_version.file.byte_size,
        resume_offset: @checkpoint.fetch("upload_offset", 0).to_i
      ) do |offset|
        raise TikTok::Client::Error, safe_error_code(:worker_lease_lost) unless step_save_checkpoint("upload_offset" => offset)
      end
      uploaded_bytes = response.fetch("uploaded_bytes", 0).to_i if response.is_a?(Hash)
    end

    return step_mark_outcome_unknown(safe_error_code(:upload_not_confirmed)) unless uploaded_bytes == @render_version.file.byte_size

    true
  end

  def step_confirm_upload
    return false unless step_save_checkpoint("upload_complete" => true, "status_poll_attempts" => 0)

    step_with_live_lease do
      now = Time.current
      outbound_attempt.update!(status: :confirmed, sender_stopped_at: now, provider_reference:)
      publication.update!(status: :processing, provider_reference:)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:upload_confirmed),
        stage: publish_stage
      )
      step_succeed!
    end
  end

  def step_check_publish_status
    response = tiktok_client.publish_status(
      access_token: @access_token,
      publish_id: @checkpoint.fetch("publish_id")
    )
    return step_mark_outcome_unknown(safe_error_code(:publish_status_unknown)) unless response.is_a?(Hash)
    return false unless step_handle_provider_response(response)

    status = response.dig("data", "status")
    return step_mark_published(response) if status == @configuration.fetch(:publish_statuses).fetch(:complete)
    return step_mark_failed(safe_error_code(:publish_failed)) if status == @configuration.fetch(:publish_statuses).fetch(:failed)
    return step_schedule_status_check if @configuration.fetch(:publish_statuses).fetch(:processing).include?(status)

    step_mark_outcome_unknown(safe_error_code(:publish_status_unknown))
  end

  def step_mark_published(response)
    step_load_public_video_reference(response)

    step_with_live_lease do
      now = Time.current
      publication.update!(
        status: :published,
        platform_post_id: @public_post_id,
        permalink: @permalink,
        published_at: now,
        provider_reference: provider_reference,
        safe_error_code: nil
      )
      outbound_attempt.update!(status: :confirmed, sender_stopped_at: now, safe_error_code: nil, provider_reference:)
      workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:published),
        stage: publish_stage,
        details: { publish_id: @publish_id, platform_post_id: @public_post_id, permalink: @permalink }.compact
      )
      step_succeed!
    end
  end

  def step_load_public_video_reference(response)
    @public_post_id = nil
    @permalink = nil
    public_post_id = Array(response.dig("data", @configuration.fetch(:public_post_ids_field))).first
    return unless public_post_id.present? && video_list_scope_granted?

    video = tiktok_client.video_query(access_token: @access_token, video_ids: [ public_post_id ])
    return unless video.is_a?(Hash) && video["id"].to_s == public_post_id.to_s
    return unless valid_tiktok_permalink?(video["share_url"])

    @public_post_id = public_post_id.to_s
    @permalink = video.fetch("share_url")
  rescue TikTok::Client::Error
    nil
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse
    nil
  end

  def video_list_scope_granted?
    Array(@social_connection.scopes).include?(@configuration.fetch(:video_list_scope))
  end

  def valid_tiktok_permalink?(value)
    uri = URI(value.to_s)
    allowed_hosts = @configuration.fetch(:permalink_hosts)
    uri.is_a?(URI::HTTPS) && allowed_hosts.include?(uri.host&.downcase) && uri.port == 443 && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end

  def step_schedule_status_check
    attempts = @checkpoint.fetch("status_poll_attempts", 0).to_i + 1
    return step_mark_outcome_unknown(safe_error_code(:publish_status_unknown)) if attempts >= max_status_poll_attempts
    return false unless step_save_checkpoint("status_poll_attempts" => attempts)

    scheduled = step_with_live_lease do
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
    return false unless scheduled

    Publications::PublishJob.set(wait: status_poll_interval).perform_later(workflow_run.id)
    success?
  end

  def step_mark_failed(error_code)
    step_with_live_lease do
      now = Time.current
      outbound_attempt.update!(status: :failed, sender_stopped_at: now, safe_error_code: error_code, provider_reference:)
      publication.update!(status: :failed, safe_error_code: error_code, provider_reference: provider_reference)
      workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:failed),
        stage: publish_stage,
        details: { safe_error_code: error_code }
      )
      step_fail!("TikTok không hoàn tất bài đăng. Mã lỗi an toàn: #{error_code}.")
    end
  end

  def step_mark_outcome_unknown(error_code)
    step_with_live_lease do
      now = Time.current
      outbound_attempt.update!(status: :outcome_unknown, sender_stopped_at: now, safe_error_code: error_code, provider_reference:)
      publication.update!(
        status: :outcome_unknown,
        provider_reference: provider_reference,
        safe_error_code: error_code
      )
      workflow_run.update!(status: :reconciliation_required, worker_id: nil, lease_expires_at: nil)
      workflow_run.workflow_audit_events.create!(
        outbound_attempt:,
        event_type: audit_event(:outcome_unknown),
        stage: publish_stage,
        details: { safe_error_code: error_code }
      )
      step_fail!("TikTok chưa xác nhận được kết quả đăng; cần đối soát trước khi thử lại.")
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

  def step_handle_provider_response(response)
    error_code = provider_error_code(response)
    return true if provider_success?(response)
    return step_mark_failed(provider_safe_error_code(error_code)) if outbound_attempt

    step_record_provider_cap(error_code) if provider_cap_error?(error_code)
    step_record_pre_send_failure(:creator_info_unavailable) unless provider_cap_error?(error_code)
  end

  def step_handle_client_error(error)
    error_code = error.code
    return step_record_pre_send_failure(:creator_info_unavailable) unless outbound_attempt
    return step_mark_outcome_unknown(error_code) if ambiguous_error?(error_code)

    step_mark_failed(provider_safe_error_code(error_code))
  end

  def ambiguous_error?(error_code)
    @configuration.fetch(:ambiguous_error_codes).include?(error_code) ||
      error_code.start_with?(@configuration.fetch(:ambiguous_http_error_prefix))
  end

  def step_record_pre_send_failure(error_key)
    error_code = safe_error_code(error_key)
    return step_require_schedule_consent_confirmation(error_key, error_code) if schedule_consent_requires_confirmation?(error_key)

    publication.update!(safe_error_code: error_code)
    step_fail!(pre_send_failure_message(error_key))
  end

  def schedule_consent_requires_confirmation?(error_key)
    publication.schedule_occurrence_id.present? && %i[privacy_unavailable interaction_disabled].include?(error_key)
  end

  def step_require_schedule_consent_confirmation(error_key, error_code)
    WorkflowRun.transaction do
      @workflow_run = WorkflowRun.lock.find(workflow_run.id)
      @publication = Publication.lock.find(publication.id)
      schedule = Schedule.lock.find(publication.schedule_occurrence.schedule_id)
      schedule.update!(status: :paused) if schedule.active?
      publication.update!(status: :draft, safe_error_code: error_code)
      workflow_run.update!(status: :failed, worker_id: nil, lease_expires_at: nil)
    end
    step_fail!(pre_send_failure_message(error_key))
  end

  def provider_error_code(response)
    response.dig("error", "code") if response.is_a?(Hash) && response["error"].is_a?(Hash)
  end

  def provider_success?(response)
    response.is_a?(Hash) && provider_error_code(response).in?([ nil, @configuration.fetch(:successful_response_code) ])
  end

  def provider_cap_error?(error_code)
    @configuration.fetch(:provider_cap_errors).value?(error_code)
  end

  def provider_safe_error_code(error_code)
    return safe_error_code(:creator_cap_reached) if error_code == @configuration.fetch(:provider_cap_errors).fetch(:creator)
    return safe_error_code(:provider_app_cap_reached) if error_code == @configuration.fetch(:provider_cap_errors).fetch(:app)

    error_code.presence || safe_error_code(:creator_info_unavailable)
  end

  def safe_error_code(key)
    @configuration.fetch(:safe_error_codes).fetch(key)
  end

  def pre_send_failure_message(error_key)
    case error_key
    when :missing_privacy_choice
      "Chọn quyền riêng tư trước khi đăng lên TikTok."
    when :caption_too_long
      "Caption vượt quá giới hạn ký tự TikTok cho phép."
    when :privacy_not_allowed
      "TikTok chưa cho phép đăng công khai qua ứng dụng này."
    when :privacy_unavailable
      "Quyền riêng tư đã chọn không còn được tài khoản TikTok cho phép."
    when :private_account_not_confirmed
      "Xác nhận tài khoản TikTok đang ở chế độ riêng tư trước khi đăng."
    when :music_usage_not_confirmed
      "Xác nhận quyền sử dụng nhạc trước khi đăng lên TikTok."
    when :ai_disclosure_not_confirmed
      "Xác nhận video có nội dung do AI tạo hay không trước khi đăng lên TikTok."
    when :interaction_disabled
      "Cài đặt creator hiện tại không cho phép lựa chọn tương tác đã lưu."
    when :branded_content_self_only
      "Không thể chọn nội dung thương hiệu cùng quyền riêng tư SELF_ONLY."
    when :creator_cap_reached
      "TikTok báo tài khoản creator đã chạm giới hạn đăng hiện tại."
    when :provider_app_cap_reached
      "TikTok báo ứng dụng đã chạm giới hạn creator đang hoạt động."
    when :app_local_cap_reached
      "AffiHub đã dùng đủ số tài khoản TikTok mới cho phép trong 24 giờ gần đây."
    else
      "Không thể xác minh cài đặt creator hiện tại trên TikTok."
    end
  end

  def provider_reference
    { provider: provider_key, publish_id: @publish_id || @checkpoint["publish_id"] }.compact
  end

  def tiktok_client
    @tiktok_client ||= @configuration.fetch(:client_class).constantize.new
  end

  def provider_key
    @configuration.fetch(:provider_key).to_s
  end

  def publish_stage
    @configuration.fetch(:publish_stage)
  end

  def audit_event(key)
    @configuration.fetch(:audit_events).fetch(key)
  end

  def worker_id
    @worker_id ||= "#{@configuration.fetch(:worker_id_prefix)}-#{SecureRandom.uuid}"
  end

  def client_error_code(key)
    @configuration.fetch(:client_error_codes).fetch(key)
  end

  def request_timeout
    @configuration.fetch(:upload_timeout_seconds).to_i +
      (@configuration.fetch(:read_timeout_seconds).to_i * 3) +
      (@configuration.fetch(:open_timeout_seconds).to_i * 4)
  end

  def status_poll_interval
    @configuration.fetch(:status_poll_interval_seconds).to_i.seconds
  end

  def max_status_poll_attempts
    @configuration.fetch(:status_poll_max_attempts).to_i
  end
end
