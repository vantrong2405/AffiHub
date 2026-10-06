# frozen_string_literal: true

# Validates a local MP4 upload for the video preview flow.
class VideoImportForm < MainForm
  attribute :file

  validates :file, presence: { message: "Chọn một tệp MP4 để xem trước." }
  validate :file_is_mp4

  private

  # Rejects uploads whose MIME type or filename does not identify an MP4.
  def file_is_mp4
    return if file.blank?

    filename = file.respond_to?(:original_filename) ? file.original_filename : nil
    content_type = file.respond_to?(:content_type) ? file.content_type : nil
    return if File.extname(filename.to_s).casecmp?(".mp4") && content_type == "video/mp4"

    errors.add(:file, "Chọn tệp MP4. Tệp MOV sẽ khả dụng khi có chuyển mã video.")
  end
end
