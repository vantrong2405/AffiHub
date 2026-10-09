class DriveExports::UpdateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  DRIVE_CONFIGURATION = CONFIGURATION.fetch(:drive)

  attr_reader :drive_export

  # Initializes a manual reconciliation decision for one uncertain Drive upload.
  #
  # @param video_project_id [Integer] the project owning the render
  # @param drive_export_id [Integer] the uncertain Drive export
  # @param decision [String] the user's occurred, not_occurred, or unknown decision
  # @param evidence [String] the user's explanation of the manual check
  # @param actor_reference [String] the local operator reference
  # @param provider_reference [String, nil] the Drive file URL when the upload occurred
  # @param risk_confirmed [Boolean] confirmation before a retry after not_occurred
  # @return [DriveExports::UpdateService] the configured service
  def initialize(video_project_id:, drive_export_id:, decision:, evidence:, actor_reference:,
                 provider_reference: nil, risk_confirmed: false)
    @video_project_id = video_project_id
    @drive_export_id = drive_export_id
    @decision = decision.to_s
    @evidence = evidence.to_s.strip
    @actor_reference = actor_reference.to_s.strip
    @provider_reference = provider_reference.to_s.strip
    @risk_confirmed = ActiveModel::Type::Boolean.new.cast(risk_confirmed)
    super()
  end

  # Records the user's manual result and retries only after explicit risk confirmation.
  #
  # @return [Boolean] whether the reconciliation decision was recorded
  def call
    return false unless step_load_export
    return false unless step_validate_decision
    return false unless step_apply_decision

    step_enqueue_safe_retry if @decision == "not_occurred"
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu kết quả đối soát Drive.")
  end

  private

  def step_load_export
    @drive_export = DriveExport.joins(:render_version)
      .find_by(id: @drive_export_id, render_versions: { video_project_id: @video_project_id })
    return true if drive_export

    step_fail!("Không tìm thấy bản xuất Drive trong project này.")
  end

  def step_validate_decision
    allowed_decisions = CONFIGURATION.dig(:drive_export, :outcome_decisions)
    return step_fail!("Kết quả đối soát Drive không hợp lệ.") unless allowed_decisions.include?(@decision)
    return step_fail!("Bản xuất Drive không còn chờ đối soát.") unless drive_export.outcome_unknown?
    return step_fail!("Hãy ghi lại bằng chứng kiểm tra Drive.") if @evidence.blank?
    return step_fail!("Nội dung bằng chứng vượt quá giới hạn.") if
      @evidence.length > CONFIGURATION.dig(:drive_export, :manual_evidence_max_characters)
    return step_fail!("Hãy ghi lại người thực hiện đối soát.") if @actor_reference.blank?
    return step_fail!("Hãy xác nhận rủi ro trước khi thử upload lại.") if @decision == "not_occurred" && !@risk_confirmed

    if @decision == "occurred" && step_drive_file_id.blank?
      return step_fail!("Link bằng chứng phải trỏ tới file trong Google Drive.")
    end

    true
  end

  def step_apply_decision
    @workflow_run = drive_export.workflow_runs.find_by(
      operation: DRIVE_CONFIGURATION.fetch(:workflow_operation),
      stage: DRIVE_CONFIGURATION.fetch(:workflow_stage)
    )
    return step_fail!("Không tìm thấy workflow cần đối soát.") unless @workflow_run&.outcome_unknown?

    DriveExport.transaction do
      @workflow_run.lock!
      drive_export.lock!
      step_save_decision
      step_record_decision
    end
    true
  end

  def step_save_decision
    case @decision
    when "occurred"
      drive_export.update!(
        status: :manual_outcome_confirmed,
        drive_file_id: step_drive_file_id,
        drive_url: @provider_reference,
        upload_session_uri: nil,
        upload_offset: 0,
        safe_error_code: nil
      )
      @workflow_run.update!(status: :completed, worker_id: nil, lease_expires_at: nil)
    when "not_occurred"
      drive_export.update!(status: :queued, safe_error_code: nil)
      @workflow_run.update!(status: :queued, worker_id: nil, lease_expires_at: nil)
    else
      drive_export.update!(status: :outcome_unknown)
      @workflow_run.update!(status: :outcome_unknown, worker_id: nil, lease_expires_at: nil)
    end
  end

  def step_record_decision
    details = {
      "decision" => @decision,
      "evidence" => @evidence,
      "actor_reference" => @actor_reference
    }
    details["provider_reference"] = @provider_reference if @decision == "occurred"
    details["risk_confirmed"] = @risk_confirmed if @decision != "occurred"

    @workflow_run.workflow_audit_events.create!(
      event_type: DRIVE_CONFIGURATION.fetch(:audit_events).fetch(:manual_outcome),
      stage: @workflow_run.stage,
      worker_id: @actor_reference,
      fencing_token: @workflow_run.fencing_token,
      details:
    )
  end

  def step_enqueue_safe_retry
    DriveExports::UploadJob.perform_later(drive_export.id)
  end

  def step_drive_file_id
    uri = URI(@provider_reference)
    return unless uri.is_a?(URI::HTTPS) && uri.host == "drive.google.com" && uri.userinfo.nil?

    match = uri.path.match(%r{\A/file/d/([A-Za-z0-9_-]+)(?:/|\z)})
    match && match[1]
  rescue URI::InvalidURIError
    nil
  end
end
