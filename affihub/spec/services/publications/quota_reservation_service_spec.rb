require "rails_helper"

RSpec.describe Publications::QuotaReservationService, type: :service do
  describe "#call" do
    let(:social_destination) { create(:social_destination) }
    let(:publication) { create(:publication, social_destination:) }

    it "returns a reservation for a new Publication" do
      service = described_class.new(publication_id: publication.id)

      expect { service.call }.to change(PublicationQuotaReservation, :count).by(1)

      expect(service.success?).to eq(true)
      expect(service.reservation.publication).to eq(publication)
      expect(service.next_available_at).to eq(nil)
    end

    it "returns the existing reservation for a Publication retry" do
      service = described_class.new(publication_id: publication.id)
      service.call
      original_reservation = service.reservation

      retry_service = described_class.new(publication_id: publication.id)

      expect { retry_service.call }.not_to change(PublicationQuotaReservation, :count)

      expect(retry_service.success?).to eq(true)
      expect(retry_service.reservation).to eq(original_reservation)
    end

    context "when five Publications used the destination in the last 24 hours" do
      let!(:reservations) do
        create_list(:publication_quota_reservation, 5, social_destination:, reserved_at: 30.minutes.ago)
      end

      it "returns the exact time the oldest reservation leaves the window" do
        service = described_class.new(publication_id: publication.id)

        expect { service.call }.not_to change(PublicationQuotaReservation, :count)

        expect(service.success?).to eq(false)
        expect(service.next_available_at).to eq(reservations.first.reserved_at + 24.hours)
      end
    end

    context "when an old reservation is outside the rolling 24-hour window" do
      let!(:expired_reservation) do
        create(:publication_quota_reservation, social_destination:, reserved_at: 25.hours.ago)
      end

      it "returns a new reservation" do
        service = described_class.new(publication_id: publication.id)

        expect { service.call }.to change(PublicationQuotaReservation, :count).by(1)

        expect(service.success?).to eq(true)
        expect(service.reservation.publication).to eq(publication)
      end
    end

    context "when two Publications compete for the final destination slot" do
      it "returns a reservation to only one Publication", database_cleaner: :truncation do
        create_list(:publication_quota_reservation, 4, social_destination:, reserved_at: 30.minutes.ago)
        first_publication = create(:publication, social_destination:)
        second_publication = create(:publication, social_destination:)
        publication_ids = [ first_publication.id, second_publication.id ]
        ready = Queue.new
        start = Queue.new
        results = Queue.new

        threads = publication_ids.map do |publication_id|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              service = described_class.new(publication_id:)
              service.call
              results << service.success?
            end
          end
        end
        2.times { ready.pop }
        2.times { start << true }
        threads.each(&:value)

        outcomes = 2.times.map { results.pop }

        expect(outcomes.count(true)).to eq(1)
        expect(outcomes.count(false)).to eq(1)
        expect(PublicationQuotaReservation.where(social_destination:).count).to eq(5)
      end
    end
  end
end
