# frozen_string_literal: true

# Imports a local MP4 and creates its source and ready-to-preview render.
class VideoImportService
  attr_reader :form, :video_project, :source_asset, :render_version

  # Validates the uploaded file before importing it.
  #
  # @param file [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile] local video file
  # @return [VideoImportService]
  def initialize(file:)
    @form = VideoImportForm.new(file: file)
  end

  # Imports the video when the upload form is valid.
  #
  # @return [VideoImportService] this service with its result or validation errors
  def call
    return self unless form.valid?

    create_local_preview
    self
  rescue ActiveRecord::RecordInvalid => error
    form.errors.add(:base, error.record.errors.full_messages.to_sentence)
    self
  end

  # Reports whether the import created a project successfully.
  #
  # @return [Boolean]
  def success?
    video_project.present? && form.errors.empty?
  end

  # Returns upload validation and persistence errors.
  #
  # @return [ActiveModel::Errors]
  def errors
    form.errors
  end

  private

  # Persists the project records and attaches the same immutable MP4 to source and render.
  def create_local_preview
    file = form.file
    title = File.basename(file.original_filename, File.extname(file.original_filename))

    VideoProject.transaction do
      @video_project = VideoProject.create!(title: title.presence || "Video")
      @source_asset = video_project.source_assets.create!(
        source_type: "local_upload",
        provenance: { "source" => "local_upload" }
      )
      source_asset.file.attach(file)

      @render_version = source_asset.render_versions.create!(status: :ready, metadata: {})
      render_version.file.attach(source_asset.file.blob)
    end
  end
end
