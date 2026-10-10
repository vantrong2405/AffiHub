require "rails_helper"

RSpec.describe Youtube::QuotaReservationService, type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#call" do
    it "returns separate local counts for search.list and videos.insert" do
      search_reservation = described_class.new(bucket: :search_list)
      upload_reservation = described_class.new(bucket: :videos_insert)

      expect(search_reservation.call).to eq(true)
      expect(upload_reservation.call).to eq(true)
      expect(search_reservation.observed_count).to eq(1)
      expect(upload_reservation.observed_count).to eq(1)
      expect(YoutubeQuotaCounter.order(:bucket).pluck(:bucket, :requests_count)).to eq([
        [ "search.list", 1 ], [ "videos.insert", 1 ]
      ])
    end

    it "returns false only for the exhausted local bucket" do
      configuration = Rails.application.config_for(:youtube).deep_symbolize_keys
      configuration[:quota][:buckets][:search_list][:daily_limit] = 1
      allow(Rails.application).to receive(:config_for).with(:youtube).and_return(configuration)
      expect(described_class.new(bucket: :search_list).call).to eq(true)

      exhausted_search = described_class.new(bucket: :search_list)
      upload_reservation = described_class.new(bucket: :videos_insert)

      expect(exhausted_search.call).to eq(false)
      expect(upload_reservation.call).to eq(true)
      expect(YoutubeQuotaCounter.find_by!(bucket: "search.list").requests_count).to eq(1)
      expect(YoutubeQuotaCounter.find_by!(bucket: "videos.insert").requests_count).to eq(1)
    end

    it "returns a new counter after midnight Pacific Time" do
      first_day = described_class.new(bucket: :search_list)
      second_day = described_class.new(bucket: :search_list)

      travel_to(Time.utc(2026, 10, 8, 6, 59, 0)) { expect(first_day.call).to eq(true) }
      travel_to(Time.utc(2026, 10, 8, 7, 1, 0)) { expect(second_day.call).to eq(true) }

      expect(YoutubeQuotaCounter.order(:usage_date).pluck(:usage_date, :requests_count)).to eq([
        [ Date.new(2026, 10, 7), 1 ], [ Date.new(2026, 10, 8), 1 ]
      ])
    end
  end
end
