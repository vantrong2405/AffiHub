class RenderVersion < ApplicationRecord
  belongs_to :source_asset, inverse_of: :render_versions
  has_one_attached :file

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }
end
