class ProjectMediaAssets::CreateService < ApplicationService
  ALLOWED_CONTENT_TYPES = %w[image/png image/jpeg image/webp].freeze
  WORKFLOW_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys

  attr_reader :project_media_asset

  # Initializes a static image upload for one video project.
  #
  # @param video_project [VideoProject] the project that owns the image
  # @param file [ActionDispatch::Http::UploadedFile] the uploaded PNG, JPEG, or WebP
  # @return [ProjectMediaAssets::CreateService] the configured service
  def initialize(video_project:, file:)
    @video_project = video_project
    @file = file
    super()
  end

  # Validates and saves a project-owned image without queueing background work.
  #
  # @return [Boolean] whether the image asset was created
  def call
    return false unless step_validate_upload
    return false unless step_persist_asset

    step_succeed!
    success?
  end

  private

  def step_validate_upload
    return step_fail!("Hãy chọn một project hợp lệ.") unless @video_project&.persisted?
    return step_fail!("Hãy chọn một file PNG, JPEG hoặc WebP.") unless @file.respond_to?(:tempfile)
    return step_fail!("MIME của file không được hỗ trợ.") unless ALLOWED_CONTENT_TYPES.include?(declared_content_type)
    return step_fail!("File rỗng hoặc vượt quá giới hạn cấu hình.") unless upload_size.positive? && upload_size <= asset_file_max_bytes
    return step_fail!("Chữ ký file không khớp với PNG, JPEG hoặc WebP.") unless valid_file_signature?

    true
  end

  def step_persist_asset
    @project_media_asset = @video_project.project_media_assets.build
    @project_media_asset.file.attach(@file)
    return true if @project_media_asset.save

    step_fail!(@project_media_asset.errors.full_messages.to_sentence)
  end

  def declared_content_type
    @file.content_type.to_s.split(";").first.to_s.strip.downcase
  end

  def upload_size
    @file.size.to_i
  end

  def asset_file_max_bytes
    WORKFLOW_CONFIGURATION.dig(:limits, :project_media_asset_max_bytes)
  end

  def valid_file_signature?
    tempfile = @file.tempfile
    tempfile.binmode
    tempfile.rewind
    signature = tempfile.read(12).to_s

    case declared_content_type
    when "image/png"
      signature.start_with?("\x89PNG\r\n\x1A\n".b)
    when "image/jpeg"
      signature.start_with?("\xFF\xD8\xFF".b)
    when "image/webp"
      signature.byteslice(0, 4) == "RIFF" && signature.byteslice(8, 4) == "WEBP"
    else
      false
    end
  ensure
    tempfile&.rewind
  end
end
