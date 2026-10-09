class DriveExports::CreateService < ApplicationService
  CONFIGURATION = Rails.application.config_for(:google).deep_symbolize_keys
  DRIVE_CONFIGURATION = CONFIGURATION.fetch(:drive)

  attr_reader :drive_export, :video_project

  # Initializes a requested Google Drive export for a project render.
  #
  # @param video_project_id [Integer] the project that owns the selected render
  # @param render_version_id [Integer] the immutable render version to export
  # @param google_connection_id [Integer] the connected Drive account
  # @return [DriveExports::CreateService] the configured service
  def initialize(video_project_id:, render_version_id:, google_connection_id:)
    @video_project_id = video_project_id
    @render_version_id = render_version_id
    @google_connection_id = google_connection_id
    super()
  end

  # Creates or safely requeues one Drive export without duplicating active jobs.
  #
  # @return [Boolean] whether the export request was accepted
  def call
    @enqueue_upload = false
    return false unless step_load_resources
    return false unless step_validate_request
    return false unless step_create_or_requeue_export

    step_enqueue_upload if @enqueue_upload
    step_succeed!
    success?
  rescue ActiveRecord::RecordNotUnique
    step_fail!("Yêu cầu đồng bộ Drive đã được tạo ở một thao tác khác.")
  rescue ActiveRecord::RecordInvalid
    step_fail!("Không thể lưu yêu cầu đồng bộ Drive.")
  end

  private

  def step_load_resources
    @video_project = VideoProject.find_by(id: @video_project_id)
    return step_fail!("Không tìm thấy project video.") unless video_project

    @render_version = RenderVersion.find_by(id: @render_version_id, video_project_id: video_project.id)
    return step_fail!("Không tìm thấy bản render trong project này.") unless @render_version

    @google_connection = GoogleConnection.find_by(id: @google_connection_id)
    return step_fail!("Không tìm thấy kết nối Google Drive.") unless @google_connection

    true
  end

  def step_validate_request
    return step_fail!("Chỉ hỗ trợ đồng bộ bản render MP4 đã sẵn sàng.") unless
      @render_version.ready? && @render_version.file.attached?
    return step_fail!("Kết nối đã chọn không phải Google Drive.") unless @google_connection.integration == "drive"
    return step_fail!("Google Drive cần kết nối lại trước khi đồng bộ.") unless @google_connection.connected?

    true
  end

  def step_create_or_requeue_export
    DriveExport.transaction do
      @render_version.lock!
      @drive_export = DriveExport.find_by(
        render_version_id: @render_version.id,
        google_connection_id: @google_connection.id
      )

      if @drive_export.nil?
        @drive_export = DriveExport.create!(
          google_connection: @google_connection,
          render_version: @render_version,
          folder_key: step_folder_key,
          file_key: step_file_key,
          status: :queued
        )
        @enqueue_upload = true
      elsif step_retryable_export?
        @drive_export.update!(status: :queued, safe_error_code: nil)
        @enqueue_upload = true
      end
    end
    true
  end

  def step_folder_key
    "#{DRIVE_CONFIGURATION.fetch(:folder_key_prefix)}#{video_project.id}"
  end

  def step_file_key
    "#{DRIVE_CONFIGURATION.fetch(:file_key_prefix)}render-#{@render_version.id}-connection-#{@google_connection.id}"
  end

  def step_retryable_export?
    @drive_export.waiting_for_quota? || @drive_export.storage_quota_exceeded? || @drive_export.failed?
  end

  def step_enqueue_upload
    DriveExports::UploadJob.perform_later(drive_export.id)
  end
end
