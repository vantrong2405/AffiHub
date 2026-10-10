class SourceDownloadGate < ApplicationRecord
  validates :key, presence: true
end
