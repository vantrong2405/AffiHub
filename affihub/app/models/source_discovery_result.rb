class SourceDiscoveryResult < ApplicationRecord
  belongs_to :source_discovery, inverse_of: :source_discovery_results
  belongs_to :youtube_discovery_metadata, inverse_of: :source_discovery_results

  validates :position, presence: true, uniqueness: { scope: :source_discovery_id }
  validates :youtube_discovery_metadata_id, uniqueness: { scope: :source_discovery_id }
end
