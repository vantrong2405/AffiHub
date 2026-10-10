# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAssets::ReserveDownloadSlotService, type: :service do
  describe "#call" do
    it "reserves a start while the rolling window has capacity" do
      service = described_class.new

      expect { service.call }.to change(SourceDownloadSlot, :count).by(1)

      expect(service).to be_success
    end

    context "when ten download starts are still inside the rolling hour" do
      let!(:recent_download_slots) do
        create_list(:source_download_slot, 10, started_at: 30.minutes.ago)
      end

      it "returns the next available time without reserving another start" do
        service = described_class.new

        expect { service.call }.not_to change(SourceDownloadSlot, :count)

        expect(service).not_to be_success
        expect(service.next_available_at).to eq(recent_download_slots.first.started_at + 60.minutes)
      end
    end

    context "when the oldest start is outside the rolling hour" do
      before do
        create(:source_download_slot, started_at: 61.minutes.ago)
        create_list(:source_download_slot, 9, started_at: 30.minutes.ago)
      end

      it "reserves the newly available start" do
        service = described_class.new

        expect { service.call }.to change(SourceDownloadSlot, :count).by(1)

        expect(service).to be_success
      end
    end

    context "when two workers compete for the final start" do
      before { create_list(:source_download_slot, 9, started_at: 30.minutes.ago) }

      it "grants exactly one reservation", database_cleaner: :truncation do
        first_worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.new.call
          end
        end
        second_worker = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            described_class.new.call
          end
        end

        first_result = first_worker.value
        second_result = second_worker.value

        expect([ first_result, second_result ]).to contain_exactly(true, false)
        expect(SourceDownloadSlot.count).to eq(10)
      end
    end
  end
end
