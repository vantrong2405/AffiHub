class VideoProject < ApplicationRecord
  has_many :source_assets, inverse_of: :video_project
  has_many :render_versions, through: :source_assets

  enum :status, { draft: 0, processing: 1, ready: 2, failed: 3 }
end
