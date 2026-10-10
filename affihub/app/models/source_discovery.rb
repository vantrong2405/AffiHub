class SourceDiscovery < ApplicationRecord
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys
    .fetch(:discovery)
    .fetch(:search_types)

  SEARCH_TYPES = CONFIGURATION.values.freeze

  belongs_to :video_project, inverse_of: :source_discoveries
  has_many :source_discovery_results, -> { order(:position) }, inverse_of: :source_discovery, dependent: :delete_all
  has_many :youtube_discovery_metadata, through: :source_discovery_results

  validates :search_type, inclusion: { in: SEARCH_TYPES }
  validates :region_code, :searched_at, presence: true
end
