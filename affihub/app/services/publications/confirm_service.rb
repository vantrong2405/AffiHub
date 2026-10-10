class Publications::ConfirmService < ApplicationService
  # The project that owns the approved Publication.
  # @return [VideoProject]
  attr_reader :video_project

  attr_reader :publication, :workflow_run

  # Initializes confirmation of one project draft after its destination passes preflight.
  #
  # @param video_project_id [Integer] the project that owns the Publication
  # @param publication_id [Integer] the draft approved for publication
  # @param preflight_report_id [Integer] the report used to verify readiness
  # @return [Publications::ConfirmService] the configured service
  def initialize(video_project_id:, publication_id:, preflight_report_id:)
    @video_project_id = video_project_id
    @publication_id = publication_id
    @preflight_report_id = preflight_report_id
    super()
  end

  # Approves the reviewed draft and queues its publication workflow.
  #
  # @return [Boolean] whether the publication workflow was queued
  def call
    return false unless step_approve_publication

    step_enqueue_publish_job
    step_enqueue_drive_exports
    step_succeed!
    success?
  rescue ActiveRecord::RecordInvalid => error
    step_fail!(error.record.errors.full_messages.to_sentence)
  end

  private

  def step_approve_publication
    Publication.transaction do
      @video_project = VideoProject.find(@video_project_id)
      @publication = video_project.publications.lock.find(@publication_id)
      return step_fail!("Chỉ được xác nhận Publication ở trạng thái bản nháp.") unless publication.draft?

      @preflight_report = publication.render_version.preflight_reports.recent_first.first
      return step_fail!("Không tìm thấy báo cáo preflight.") unless @preflight_report
      return step_fail!("Báo cáo preflight đã thay đổi. Hãy tải lại trang review.") unless latest_report_selected?
      return step_fail!("Destination không sẵn sàng theo báo cáo preflight.") unless destination_ready?
      return false unless step_validate_provider_consent

      return false unless step_create_workflow_run
      publication.update!(status: :approved)
    end
  end

  def step_create_workflow_run
    operation_id = "publication-#{publication.id}-publish"
    @workflow_run = publication.workflow_runs.find_by(operation_id:)
    if @workflow_run
      return step_fail!("Workflow cũ đã có outbound attempt và không thể xác nhận lại như bản nháp.") unless
        @workflow_run.failed? && @workflow_run.outbound_attempts.none?

      @workflow_run.update!(status: :queued, worker_id: nil, lease_expires_at: nil, checkpoint: {})
    else
      @workflow_run = publication.workflow_runs.create!(
        operation_id:,
        operation: "publication_publish",
        stage: "publish",
        status: :queued
      )
    end

    step_mark_explicit_schedule_confirmation
  end

  def step_mark_explicit_schedule_confirmation
    return true unless publication.schedule_occurrence_id

    checkpoint = workflow_run.checkpoint.to_h.stringify_keys
      .merge("scheduled_manual_confirmation_at" => Time.current.iso8601)
    workflow_run.update!(checkpoint:)
  end

  def step_enqueue_publish_job
    Publications::PublishJob.perform_later(workflow_run.id)
  end

  def step_enqueue_drive_exports
    GoogleConnection.where(integration: "drive", status: :connected).find_each do |google_connection|
      DriveExports::CreateService.new(
        video_project_id: video_project.id,
        render_version_id: publication.render_version_id,
        google_connection_id: google_connection.id
      ).call
    end
  end

  def destination_ready?
    @preflight_report.ready_for?(
      render_version: publication.render_version,
      social_destination: publication.social_destination
    )
  end

  def latest_report_selected?
    @preflight_report.id.to_s == @preflight_report_id.to_s
  end

  def step_validate_provider_consent
    return step_validate_youtube_consent if publication.social_destination.provider == "youtube"
    return step_validate_tiktok_consent if publication.social_destination.provider == "tiktok"

    true
  end

  def step_validate_youtube_consent
    return true unless publication.social_destination.provider == "youtube"

    snapshot = publication.consent_snapshot.to_h.stringify_keys
    return step_fail!("Hãy xác nhận điều khoản upload YouTube trước khi tiếp tục.") unless snapshot["upload_terms_confirmed"] == true && snapshot["confirmed_at"].present?
    return step_fail!("Xác nhận upload YouTube không khớp tài khoản, kênh, render hoặc Publication hiện tại.") unless youtube_consent_bound_to_publication?(snapshot)
    return step_fail!("Chọn quyền riêng tư video YouTube hợp lệ.") unless youtube_privacy_choice_allowed?(snapshot)
    return step_fail!("Hãy khai báo video có dành cho trẻ em hay không.") unless youtube_boolean_consent?(snapshot, "self_declared_made_for_kids")
    return step_fail!("Hãy khai báo video có nội dung tổng hợp hoặc chỉnh sửa bằng AI hay không.") unless youtube_boolean_consent?(snapshot, "contains_synthetic_media")

    true
  end

  def youtube_consent_bound_to_publication?(snapshot)
    snapshot["youtube_account_id"].to_s == publication.social_destination.social_connection.external_user_id.to_s &&
      snapshot["youtube_channel_id"].to_s == publication.social_destination.external_id.to_s &&
      snapshot["render_version_id"].to_s == publication.render_version_id.to_s &&
      snapshot["publication_id"].to_s == publication.id.to_s
  end

  def youtube_privacy_choice_allowed?(snapshot)
    configuration = Rails.application.config_for(:youtube).deep_symbolize_keys.fetch(:publisher)
    configuration.fetch(:privacy_statuses).include?(snapshot["privacy_status"])
  end

  def youtube_boolean_consent?(snapshot, key)
    [ true, false ].include?(snapshot[key])
  end

  def step_validate_tiktok_consent
    snapshot = publication.consent_snapshot.to_h.stringify_keys
    return step_fail!("Hãy lưu quyền riêng tư và nội dung TikTok trước khi tiếp tục.") unless snapshot["privacy_level"].present? && snapshot["tiktok_confirmed_at"].present?
    return step_fail!("Xác nhận TikTok không khớp tài khoản, creator, render hoặc Publication hiện tại.") unless tiktok_consent_bound_to_publication?(snapshot)
    return step_fail!("Chọn quyền riêng tư TikTok được cấu hình cho ứng dụng.") unless tiktok_privacy_choice_allowed?(snapshot)
    return step_fail!("Hãy khai báo nội dung TikTok có sử dụng AI hay không.") unless tiktok_boolean_consent?(snapshot, "is_aigc")
    return step_fail!("Hãy xác nhận tài khoản TikTok đang ở chế độ riêng tư.") if tiktok_private_account_required? && snapshot["creator_account_private"] != true
    return step_fail!("Hãy xác nhận quyền sử dụng nhạc trong video TikTok.") if tiktok_music_confirmation_required? && snapshot["music_usage_confirmed"] != true
    return step_fail!("Hãy lưu đầy đủ lựa chọn tương tác và disclosure TikTok.") unless tiktok_boolean_consent_fields_valid?(snapshot)
    return step_fail!("Nội dung quảng bá thương hiệu khác không thể dùng quyền riêng tư Chỉ mình tôi.") if tiktok_private_branded_content?(snapshot)

    true
  end

  def tiktok_consent_bound_to_publication?(snapshot)
    social_destination = publication.social_destination
    snapshot["tiktok_social_connection_id"].to_s == social_destination.social_connection_id.to_s &&
      snapshot["tiktok_creator_id"].to_s == social_destination.external_id.to_s &&
      snapshot["tiktok_render_version_id"].to_s == publication.render_version_id.to_s &&
      snapshot["tiktok_publication_id"].to_s == publication.id.to_s
  end

  def tiktok_privacy_choice_allowed?(snapshot)
    configuration = tiktok_configuration
    return true if configuration.fetch(:content_posting_audited)

    configuration.fetch(:unaudited_allowed_privacy_levels).include?(snapshot["privacy_level"])
  end

  def tiktok_private_account_required?
    configuration = tiktok_configuration
    configuration.fetch(:unaudited_requires_private_account) && !configuration.fetch(:content_posting_audited)
  end

  def tiktok_music_confirmation_required?
    tiktok_configuration.fetch(:require_music_usage_confirmation)
  end

  def tiktok_boolean_consent_fields_valid?(snapshot)
    %w[allow_comment allow_duet allow_stitch brand_organic_toggle brand_content_toggle].all? do |key|
      tiktok_boolean_consent?(snapshot, key)
    end
  end

  def tiktok_boolean_consent?(snapshot, key)
    [ true, false ].include?(snapshot[key])
  end

  def tiktok_private_branded_content?(snapshot)
    snapshot["privacy_level"] == "SELF_ONLY" && snapshot["brand_content_toggle"] == true
  end

  def tiktok_configuration
    SocialConnections::ProviderConfiguration.for(:tiktok)
  end
end
