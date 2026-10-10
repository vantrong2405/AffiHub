# frozen_string_literal: true

require "rails_helper"

RSpec.describe Youtube::ExpireDiscoveryMetadataJob, type: :job do
  describe "#perform" do
    it "deletes YouTube discovery metadata when it reaches 30 days" do
      discovery_metadata = create(:youtube_discovery_metadata, fetched_at: 30.days.ago)

      described_class.perform_now

      expect(YoutubeDiscoveryMetadata.exists?(discovery_metadata.id)).to be(false)
    end

    it "keeps YouTube discovery metadata younger than 30 days" do
      discovery_metadata = create(:youtube_discovery_metadata, fetched_at: 29.days.ago)

      described_class.perform_now

      expect(YoutubeDiscoveryMetadata.exists?(discovery_metadata.id)).to be(true)
    end

    it "deletes expired persisted discovery searches and their result links" do
      video_project = create(:video_project)
      discovery = create(:source_discovery, video_project:, searched_at: 30.days.ago)
      metadata = create(:youtube_discovery_metadata, fetched_at: 30.days.ago)
      result = create(:source_discovery_result, source_discovery: discovery, youtube_discovery_metadata: metadata)

      described_class.perform_now

      expect(SourceDiscovery.exists?(discovery.id)).to be(false)
      expect(SourceDiscoveryResult.exists?(result.id)).to be(false)
      expect(YoutubeDiscoveryMetadata.exists?(metadata.id)).to be(false)
    end
  end
end
