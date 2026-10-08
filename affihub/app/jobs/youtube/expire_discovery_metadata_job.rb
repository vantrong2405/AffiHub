class Youtube::ExpireDiscoveryMetadataJob < ApplicationJob
  CONFIGURATION = Rails.application.config_for(:youtube).deep_symbolize_keys

  queue_as :default

  # Removes discovery metadata before the configured maximum retention age.
  #
  # @return [Integer] the number of expired metadata rows deleted
  def perform
    YoutubeDiscoveryMetadata.where(fetched_at: ..step_expiry_cutoff).delete_all
  end

  private

  def step_expiry_cutoff
    CONFIGURATION.fetch(:metadata_ttl_days).days.ago +
      CONFIGURATION.fetch(:metadata_expiry_buffer_seconds).seconds
  end
end
