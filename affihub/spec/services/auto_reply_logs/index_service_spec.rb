require "rails_helper"

RSpec.describe AutoReplyLogs::IndexService, type: :service do
  describe "#call" do
    it "returns the comment events for the requested destination in newest-first order" do
      destination = create(:social_destination)
      older_event = create(:auto_reply_event, social_destination: destination, created_at: 2.minutes.ago)
      newer_event = create(:auto_reply_event, social_destination: destination, created_at: 1.minute.ago)
      create(:auto_reply_event)
      service = described_class.new(social_destination_id: destination.id)

      expect(service.call).to eq(true)
      expect(service.events).to eq([ newer_event, older_event ])
    end
  end
end
