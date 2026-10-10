class DriveExports::UploadService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  DRIVE_CONFIGURATION = CONFIGURATION.fetch(:drive)

  attr_reader :drive_export

  # Initializes a durable Drive upload workflow for one render export.
  #
  # @param drive_export_id [Integer] the Drive export to upload
  # @return [DriveExports::UploadService] the configured service
  def initialize(drive_export_id:)
    @drive_export_id = drive_export_id
    super()
  end

  # Uploads one immutable render version to its private project folder.
  #
  # @return [Boolean] whether Drive confirmed the file metadata
  def call
    return false unless step_load_export
    return step_succeed_for_completed_export if drive_export.succeeded?
    return false unless step_validate_export
    return false unless step_prepare_workflow_run
    return false unless step_claim_workflow
    return false unless step_mark_export_uploading
    return false unless step_get_access_token
    return false unless step_find_or_create_folder
    return false unless step_find_or_upload_file

    success?
  rescue Google::Client::DailyQuotaExceeded
    step_mark_waiting_for_quota
  rescue Google::Client::StorageQuotaExceeded
    step_mark_storage_quota_exceeded
  rescue Google::Client::RateLimitError => error
    step_mark_retrying
    raise error
  rescue Google::Client::NetworkError, Timeout::Error => error
    return step_reconcile_upload_after_timeout if @upload_started

    step_mark_retrying
    raise error
  rescue Google::Client::ApiError => error
    step_mark_failed(error.reason)
  end

  private

  def step_load_export
    @drive_export = DriveExport.includes(:google_connection, render_version: :video_project).find_by(id: @drive_export_id)
    return true if drive_export

    step_fail!("Không tìm thấy bản xuất Drive cần đồng bộ.")
  end

  def step_validate_export
    return step_fail!("Chỉ hỗ trợ đồng bộ bản render MP4 đã sẵn sàng.") unless
      drive_export.render_version.ready? && drive_export.render_version.file.attached?
    return step_fail!("Kết nối Google này không dành cho Drive.") unless drive_export.google_connection.integration == "drive"
    return step_fail!("Kết quả Drive chưa rõ; cần đối soát trước khi thử lại.") if drive_export.outcome_unknown?
    return step_fail!("Bản xuất Drive đã được xác nhận thủ công; không gửi lại.") if drive_export.manual_outcome_confirmed?

    true
  end

  def step_prepare_workflow_run
    drive_export.with_lock do
      @workflow_run = drive_export.workflow_runs.find_by(
        operation: DRIVE_CONFIGURATION.fetch(:workflow_operation),
        stage: DRIVE_CONFIGURATION.fetch(:workflow_stage)
      )
      @workflow_run ||= drive_export.workflow_runs.create!(
        operation_id: SecureRandom.uuid,
        operation: DRIVE_CONFIGURATION.fetch(:workflow_operation),
        stage: DRIVE_CONFIGURATION.fetch(:workflow_stage),
        status: :queued
      )
    end
    true
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể khởi tạo workflow đồng bộ Drive.")
  end

  def step_claim_workflow
    @worker_id = "#{DRIVE_CONFIGURATION.fetch(:worker_id_prefix)}-#{SecureRandom.hex(8)}"
    claim_service = WorkflowRuns::ClaimService.new(
      workflow_run_id: @workflow_run.id,
      worker_id: @worker_id,
      lease_duration: CONFIGURATION.dig(:requests, :upload_timeout_seconds).seconds + 30.seconds
    )
    return step_fail!(claim_service.errors.full_messages.to_sentence) unless claim_service.call

    @workflow_run = claim_service.workflow_run
    @fencing_token = claim_service.fencing_token
    true
  rescue ActiveRecord::RecordInvalid
    step_fail!(claim_service.errors.full_messages.to_sentence)
  end

  def step_get_access_token
    token_service = GoogleConnections::AccessTokenService.new(
      google_connection_id: drive_export.google_connection_id
    )
    return step_mark_failed(DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:reconnect_required)) unless
      token_service.call

    @google_client = Google::Client.new(access_token: token_service.access_token)
    true
  end

  def step_mark_export_uploading
    DriveExport.transaction do
      @workflow_run.lock!
      return step_fail!("Workflow đồng bộ Drive đã mất lease.") unless step_current_lease?

      drive_export.lock!
      drive_export.update!(status: :uploading)
      @workflow_run.workflow_audit_events.create!(
        event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:upload_started),
        stage: @workflow_run.stage,
        worker_id: @worker_id,
        fencing_token: @fencing_token,
        details: { "status" => DriveExport.statuses.fetch(:uploading) }
      )
    end
    true
  end

  def step_find_or_create_folder
    @folder_key = "#{DRIVE_CONFIGURATION.fetch(:folder_key_prefix)}#{drive_export.render_version.video_project_id}"
    @file_key = "#{DRIVE_CONFIGURATION.fetch(:file_key_prefix)}render-#{drive_export.render_version_id}-connection-#{drive_export.google_connection_id}"
    drive_export.update!(folder_key: @folder_key, file_key: @file_key)
    @folder = @google_client.find_folder(folder_key: @folder_key)
    return step_save_folder if @folder.present?

    begin
      @folder = @google_client.create_folder(
        folder_key: @folder_key,
        name: drive_export.render_version.video_project.name,
        parent_id: drive_export.google_connection.drive_parent_folder_id
      )
    rescue Google::Client::NetworkError
      @folder = @google_client.find_folder(folder_key: @folder_key)
      return step_mark_outcome_unknown if @folder.blank?
    end
    return step_mark_outcome_unknown if @folder.fetch("id", nil).blank?

    step_save_folder
  end

  def step_save_folder
    folder_id = @folder.fetch("id", nil)
    return step_mark_outcome_unknown if folder_id.blank?

    @drive_folder_id = folder_id
    @drive_folder_url = @folder.fetch("webViewLink", nil)
    true
  end

  def step_find_or_upload_file
    remote_file = @google_client.find_file(file_key: @file_key)
    return step_complete_export(remote_file) if remote_file.present?

    return false unless step_create_upload_session

    @upload_started = true
    upload_result = nil
    drive_export.render_version.file.open do |file|
      upload_result = @google_client.upload_file(
        session_uri: @upload_session_uri,
        file:,
        file_size: drive_export.render_version.file.byte_size,
        resume: @resume_upload_session
      ) do |offset|
        unless step_save_upload_checkpoint(offset)
          raise Google::Client::ApiError.new(
            status: nil,
            reason: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:worker_lease_lost)
          )
        end
      end
    end
    step_complete_export(upload_result)
  rescue Google::Client::NetworkError, Timeout::Error => error
    raise error unless @upload_started

    step_reconcile_upload_after_timeout
  end

  def step_create_upload_session
    @resume_upload_session = drive_export.upload_session_uri.present?
    @upload_session_uri = drive_export.upload_session_uri
    if @upload_session_uri.blank?
      @upload_session_uri = @google_client.create_upload_session(
        folder_id: @drive_folder_id,
        file_key: @file_key,
        file_name: "#{DRIVE_CONFIGURATION.fetch(:file_name_prefix)}#{@file_key}.mp4",
        file_size: drive_export.render_version.file.byte_size
      )
      drive_export.update!(upload_session_uri: @upload_session_uri, upload_offset: 0)
    end
    true
  end

  def step_save_upload_checkpoint(offset)
    saved = false
    WorkflowRun.transaction do
      checkpoint_service = WorkflowRuns::CheckpointService.new(
        workflow_run_id: @workflow_run.id,
        worker_id: @worker_id,
        fencing_token: @fencing_token,
        stage: @workflow_run.stage,
        checkpoint: { "drive_upload_offset" => offset }
      )
      next unless checkpoint_service.call

      @workflow_run = checkpoint_service.workflow_run
      drive_export.lock!
      drive_export.update!(upload_offset: offset)
      saved = true
    end
    saved
  end

  def step_reconcile_upload_after_timeout
    remote_file = @google_client.find_file(file_key: @file_key)
    return step_complete_export(remote_file) if remote_file.present?

    step_mark_outcome_unknown
  rescue Google::Client::NetworkError, Timeout::Error
    step_mark_outcome_unknown
  end

  def step_complete_export(remote_file)
    file_id = remote_file.fetch("id", nil)
    return step_mark_outcome_unknown if file_id.blank?

    DriveExport.transaction do
      @workflow_run.lock!
      return step_fail!("Workflow đồng bộ Drive đã mất lease.") unless step_current_lease?

      drive_export.lock!
      drive_export.update!(
        folder_key: @folder_key || drive_export.folder_key,
        file_key: @file_key || drive_export.file_key,
        drive_folder_id: @drive_folder_id || drive_export.drive_folder_id || remote_file.fetch("parents", []).first,
        drive_folder_url: @drive_folder_url || drive_export.drive_folder_url,
        drive_file_id: file_id,
        drive_url: remote_file.fetch("webViewLink", nil),
        upload_session_uri: nil,
        upload_offset: 0,
        safe_error_code: nil,
        status: :succeeded
      )
      @workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:uploaded),
        stage: @workflow_run.stage,
        worker_id: @worker_id,
        fencing_token: @workflow_run.fencing_token,
        details: { "drive_file_id" => file_id }
      )
    end
    SheetSyncs::EnqueueForRenderService.new(render_version_id: drive_export.render_version_id).call
    step_succeed!
  end

  def step_mark_waiting_for_quota
    step_transition_export(
      export_status: :waiting_for_quota,
      workflow_status: :queued,
      safe_error_code: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:daily_quota),
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:quota_wait)
    )
    step_fail!("Google Drive đã hết quota API miễn phí; AffiHub giữ bản xuất chờ và không bật tính phí.")
  end

  def step_mark_storage_quota_exceeded
    step_transition_export(
      export_status: :storage_quota_exceeded,
      workflow_status: :failed,
      safe_error_code: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:storage_quota),
      upload_session_uri: nil,
      upload_offset: 0,
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:storage_quota)
    )
    step_fail!("Dung lượng Drive đã đầy. Hãy tự giải phóng dung lượng; AffiHub không mua thêm storage.")
  end

  def step_mark_retrying
    step_transition_export(
      export_status: :retrying,
      workflow_status: :queued,
      safe_error_code: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:rate_limit),
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:retrying)
    )
  end

  def step_mark_outcome_unknown
    step_transition_export(
      export_status: :outcome_unknown,
      workflow_status: :outcome_unknown,
      safe_error_code: DRIVE_CONFIGURATION.fetch(:safe_error_codes).fetch(:upload_outcome_unknown),
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:outcome_unknown)
    )
    step_fail!("Google chưa xác nhận kết quả upload. AffiHub đã giữ trạng thái để đối soát trước khi gửi lại.")
  end

  def step_mark_failed(reason)
    step_transition_export(
      export_status: :failed,
      workflow_status: :failed,
      safe_error_code: reason,
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:failed)
    )
    step_fail!("Google Drive chưa thể lưu bản render.")
  end

  def step_transition_export(export_status:, workflow_status:, safe_error_code:, event_type:,
                             upload_session_uri: drive_export.upload_session_uri,
                             upload_offset: drive_export.upload_offset)
    WorkflowRun.transaction do
      @workflow_run.lock!
      return step_fail!("Workflow đồng bộ Drive đã mất lease.") unless step_current_lease?

      drive_export.lock!
      drive_export.update!(
        status: export_status,
        safe_error_code:,
        upload_session_uri:,
        upload_offset:
      )
      @workflow_run.update!(status: workflow_status, worker_id: nil, lease_expires_at: nil)
      @workflow_run.workflow_audit_events.create!(
        event_type:,
        stage: @workflow_run.stage,
        worker_id: @worker_id,
        fencing_token: @workflow_run.fencing_token,
        details: { "safe_error_code" => safe_error_code }
      )
    end
    true
  end

  def step_current_lease?
    @workflow_run.running? && @workflow_run.worker_id == @worker_id &&
      @workflow_run.fencing_token == @fencing_token &&
      @workflow_run.lease_expires_at.present? && @workflow_run.lease_expires_at > Time.current
  end

  def step_succeed_for_completed_export
    step_succeed!
    success?
  end
end
