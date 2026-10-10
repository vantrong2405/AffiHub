class SourceDownloadSlot < ApplicationRecord
  validates :started_at, presence: true
end
