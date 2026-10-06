class SourceAsset < ApplicationRecord
  belongs_to :video_project, inverse_of: :source_assets
  has_many :render_versions, inverse_of: :source_asset
  has_one_attached :file

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }
end
