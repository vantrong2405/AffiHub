require "rails_helper"

RSpec.describe MetaCommentWebhooks::ReceiveService, type: :service do
  let(:credentials) { double("credentials") }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Rails.application).to receive(:credentials).and_return(credentials)
    allow(credentials).to receive(:dig).with(:meta, :app_secret).and_return("meta-app-secret")
  end

  describe "#call" do
    it "returns success after persisting and queueing a signed Facebook comment" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      body = facebook_notification.to_json
      service = described_class.new(raw_body: body, signature: signature_for(body))

      expect(service.call).to eq(true)

      event = AutoReplyEvent.find_by!(social_destination: destination, provider_comment_id: "facebook-comment-1")
      workflow_run = WorkflowRun.find_by!(workflowable: event)
      expect(service.http_status).to eq(:ok)
      expect(event.comment_text).to eq("Mẫu này còn hàng không?")
      expect(queued_job_descriptors).to eq([ [ "AutoResponder::ProcessJob", [ workflow_run.id ] ] ])
    end

    it "rejects a signed notification whose signature does not match the raw body" do
      body = facebook_notification.to_json
      service = described_class.new(raw_body: body, signature: "sha256=invalid")

      expect(service.call).to eq(false)
      expect(service.http_status).to eq(:unauthorized)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "rejects malformed JSON after checking its signature" do
      body = "{invalid-json"
      service = described_class.new(raw_body: body, signature: signature_for(body))

      expect(service.call).to eq(false)
      expect(service.http_status).to eq(:bad_request)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "ignores a signed Facebook change whose value is not an object" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      notification = facebook_notification
      notification[:entry].first[:changes].first[:value] = "unexpected value"
      body = notification.to_json
      service = described_class.new(raw_body: body, signature: signature_for(body))

      expect(service.call).to eq(true)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "ignores a signed Facebook change whose sender is not an object" do
      destination = create(:social_destination, external_id: "facebook-page-1")
      create(:auto_reply_rule, social_destination: destination, rule_type: "default")
      notification = facebook_notification
      notification[:entry].first[:changes].first[:value][:from] = "unexpected sender"
      body = notification.to_json
      service = described_class.new(raw_body: body, signature: signature_for(body))

      expect(service.call).to eq(true)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end
  end

  def signature_for(body)
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", "meta-app-secret", body)}"
  end

  def facebook_notification
    {
      object: "page",
      entry: [
        {
          id: "facebook-page-1",
          changes: [
            {
              field: "feed",
              value: {
                item: "comment",
                verb: "add",
                comment_id: "facebook-comment-1",
                post_id: "facebook-post-1",
                message: "Mẫu này còn hàng không?",
                from: { id: "facebook-user-1" }
              }
            }
          ]
        }
      ]
    }
  end

  def queued_job_descriptors
    ActiveJob::Base.queue_adapter.enqueued_jobs.map do |job|
      [ job.fetch(:job).name, job.fetch(:args) ]
    end
  end
end
