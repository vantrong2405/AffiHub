class SourceAssets::CreateService < ApplicationService
  ALLOWED_CONTENT_TYPES = %w[video/mp4 video/quicktime application/octet-stream].freeze
  DEFAULT_PROVENANCE = { "platform" => "local", "method" => "local_upload" }.freeze
  WORKFLOW_CONFIGURATION = Rails.application.config_for(:video_workflow).deep_symbolize_keys

  attr_reader :source_asset, :video_project

  # Initializes a local source import for one video project.
  #
  # @param video_project [VideoProject] the project that owns the source
  # @param file [ActionDispatch::Http::UploadedFile] the selected MP4 or MOV file
  # @param provenance [Hash] the user-confirmed origin of the file
  # @return [SourceAssets::CreateService] the configured service
  def initialize(video_project:, file:, provenance: nil)
    @video_project = video_project
    @file = file
    @provenance = provenance
    super()
  end

  # Validates and persists a local source, then queues bounded media inspection.
  #
  # @return [Boolean] whether the source was saved and queued
  def call
    return false unless step_validate_upload
    return false unless step_persist_source

    step_enqueue_inspection
    step_succeed!
    success?
  end

  private

  def step_validate_upload
    return step_fail!("Không tìm thấy project để nhập video.") unless @video_project&.persisted?
    return step_fail!("Hãy chọn một file MP4 hoặc MOV.") unless @file.respond_to?(:tempfile)
    return step_fail!("MIME của file không được hỗ trợ.") unless ALLOWED_CONTENT_TYPES.include?(declared_content_type)
    return step_fail!("File vượt quá giới hạn cấu hình (#{source_file_max_bytes} byte).") if upload_size > source_file_max_bytes
    return step_fail!("File rỗng hoặc không có chữ ký MP4/MOV hợp lệ.") unless mp4_mov_signature?
    return step_fail!("Provenance của file không hợp lệ.") unless @provenance.nil? || @provenance.is_a?(Hash)

    true
  end

  def step_persist_source
    @source_asset = @video_project.source_assets.build(
      source_type: "local_upload",
      provenance: @provenance.presence&.deep_stringify_keys || DEFAULT_PROVENANCE
    )
    @source_asset.file.attach(@file)
    return true if @source_asset.save

    step_fail!(@source_asset.errors.full_messages.to_sentence)
  end

  def step_enqueue_inspection
    SourceAssets::InspectJob.perform_later(@source_asset.id)
  end

  def declared_content_type
    @file.content_type.to_s.split(";").first.to_s.strip.downcase
  end

  def upload_size
    @file.size.to_i
  end

  def source_file_max_bytes
    WORKFLOW_CONFIGURATION.dig(:limits, :source_file_max_bytes)
  end

  def mp4_mov_signature?
    tempfile = @file.tempfile
    tempfile.binmode
    tempfile.rewind
    tempfile.read(12).to_s.byteslice(4, 4) == "ftyp"
  ensure
    tempfile&.rewind
  end
end
