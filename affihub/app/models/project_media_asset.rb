class ProjectMediaAsset < ApplicationRecord
  belongs_to :video_project, inverse_of: :project_media_assets
  has_one_attached :file

  validate :file_must_be_attached

  private

  def file_must_be_attached
    errors.add(:file, :blank) unless file.attached?
  end
end
