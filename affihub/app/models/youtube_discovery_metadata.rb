class YoutubeDiscoveryMetadata < ApplicationRecord
  validates :video_id, :title, :channel_title, :thumbnail_url, :attribution_url,
    :discovery_type, :fetched_at, presence: true
  validates :video_id, uniqueness: true

  has_many :source_discovery_results, inverse_of: :youtube_discovery_metadata, dependent: :delete_all
end
