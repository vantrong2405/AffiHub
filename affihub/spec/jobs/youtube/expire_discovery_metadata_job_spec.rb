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
  end
end
