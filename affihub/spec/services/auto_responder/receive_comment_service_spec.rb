require "rails_helper"

RSpec.describe AutoResponder::ReceiveCommentService, type: :service do
  describe "#call" do
    let(:destination) { create(:social_destination, provider: "facebook") }

    it "persists one event and workflow when the provider replays a public comment" do
      first_service = described_class.new(
        social_destination_id: destination.id,
        source: "facebook",
        event_type: "comment",
        provider_comment_id: "fb-comment-100",
        comment_text: "Mẫu này còn hàng không?"
      )
      replayed_service = described_class.new(
        social_destination_id: destination.id,
        source: "facebook",
        event_type: "comment",
        provider_comment_id: "fb-comment-100",
        comment_text: "Mẫu này còn hàng không?"
      )

      expect(first_service.call).to eq(true)
      first_event_id = first_service.event.id
      expect(replayed_service.call).to eq(true)

      expect(replayed_service.event.id).to eq(first_event_id)
      expect(AutoReplyEvent.where(social_destination: destination, provider_comment_id: "fb-comment-100").count).to eq(1)
      expect(WorkflowRun.where(workflowable: replayed_service.event).count).to eq(1)
    end

    it "returns failure without creating an event for an unsupported conversation type" do
      service = described_class.new(
        social_destination_id: destination.id,
        source: "facebook",
        event_type: "message",
        provider_comment_id: "fb-message-101",
        comment_text: "Tin nhắn riêng"
      )

      expect(service.call).to eq(false)
      expect(AutoReplyEvent.count).to eq(0)
      expect(WorkflowRun.where(workflowable_type: "AutoReplyEvent").count).to eq(0)
    end
  end
end
