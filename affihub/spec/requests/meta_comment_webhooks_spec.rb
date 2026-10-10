require "rails_helper"

RSpec.describe "Meta comment webhooks", type: :request do
  let(:credentials) { double("credentials") }
  let(:facebook_destination) do
    create(:social_destination, external_id: "facebook-page-1")
  end
  let(:facebook_default_rule) do
    create(:auto_reply_rule,
      social_destination: facebook_destination,
      rule_type: "default",
      reply_text: "Cảm ơn bạn đã quan tâm."
    )
  end

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow(Rails.application).to receive(:credentials).and_return(credentials)
    allow(credentials).to receive(:dig).with(:meta, :app_secret).and_return("meta-app-secret")
    allow(credentials).to receive(:dig).with(:meta, :webhook_verify_token).and_return("meta-verify-token")
  end

  describe "GET /webhooks/meta/comments" do
    it "returns the challenge for a valid subscription handshake" do
      get "/webhooks/meta/comments", params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "meta-verify-token",
        "hub.challenge" => "challenge-123"
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("challenge-123")
      expect(response.media_type).to eq("text/plain")
    end

    it "rejects a subscription handshake with a different verify token" do
      get "/webhooks/meta/comments", params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "incorrect-token",
        "hub.challenge" => "challenge-123"
      }

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to eq("")
    end
  end

  describe "POST /webhooks/meta/comments" do
    it "returns HTTP 200 and queues one workflow for a signed Facebook comment" do
      destination = facebook_destination
      facebook_default_rule
      body = facebook_notification.to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      event = AutoReplyEvent.find_by!(social_destination: destination, provider_comment_id: "facebook-comment-1")
      workflow_run = WorkflowRun.find_by!(workflowable: event)

      expect(response).to have_http_status(:ok)
      expect(queued_job_descriptors).to eq([ [ "AutoResponder::ProcessJob", [ workflow_run.id ] ] ])
    end

    it "returns HTTP 200 and queues only one workflow when Meta retries a Facebook comment" do
      destination = facebook_destination
      facebook_default_rule
      body = facebook_notification.to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)
      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.where(social_destination: destination, provider_comment_id: "facebook-comment-1").count).to eq(1)
      expect(WorkflowRun.where(workflowable_type: "AutoReplyEvent").count).to eq(1)
      expect(queued_job_descriptors.length).to eq(1)
    end

    it "returns HTTP 200 without creating a reply workflow for a comment written by the Facebook Page" do
      facebook_default_rule
      body = facebook_notification(author_id: "facebook-page-1").to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "returns HTTP 200 without creating a reply workflow for a non-comment Page feed change" do
      facebook_default_rule
      body = facebook_notification(item: "photo").to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "returns HTTP 200 and queues one workflow for a signed Instagram comment" do
      destination = create(
        :social_destination,
        social_connection: create(:social_connection, provider: "instagram"),
        provider: "instagram",
        external_id: "instagram-business-1"
      )
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
      body = instagram_notification.to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      event = AutoReplyEvent.find_by!(social_destination: destination, provider_comment_id: "instagram-comment-1")
      workflow_run = WorkflowRun.find_by!(workflowable: event)

      expect(response).to have_http_status(:ok)
      expect(queued_job_descriptors).to eq([ [ "AutoResponder::ProcessJob", [ workflow_run.id ] ] ])
    end

    it "returns HTTP 200 without creating a reply workflow for an Instagram reply comment" do
      destination = create(
        :social_destination,
        social_connection: create(:social_connection, provider: "instagram"),
        provider: "instagram",
        external_id: "instagram-business-1"
      )
      create(:auto_reply_rule,
        social_destination: destination,
        rule_type: "default",
        reply_text: "Cảm ơn bạn đã quan tâm."
      )
      body = instagram_notification(parent_id: "instagram-parent-comment-1").to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "returns HTTP 200 without creating a reply workflow for an Instagram account's own comment" do
      destination = create(
        :social_destination,
        social_connection: create(:social_connection, provider: "instagram"),
        provider: "instagram",
        external_id: "instagram-business-1"
      )
      create(
        :auto_reply_rule,
        social_destination: destination,
        rule_type: "default"
      )
      body = instagram_notification(author_id: "instagram-business-1").to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "returns HTTP 200 without creating a reply workflow when the destination has no active default rule" do
      facebook_destination
      body = facebook_notification.to_json

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:ok)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "rejects a notification with an invalid signature before persisting a comment" do
      facebook_destination
      facebook_default_rule
      body = facebook_notification.to_json
      headers = signed_headers(body).merge("X-Hub-Signature-256" => "sha256=invalid")

      post "/webhooks/meta/comments", params: body, headers: headers

      expect(response).to have_http_status(:unauthorized)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end

    it "rejects malformed JSON before persisting a comment" do
      facebook_destination
      body = "{invalid-json"

      post "/webhooks/meta/comments", params: body, headers: signed_headers(body)

      expect(response).to have_http_status(:bad_request)
      expect(AutoReplyEvent.count).to eq(0)
      expect(queued_job_descriptors).to eq([])
    end
  end

  def signed_headers(body)
    signature = OpenSSL::HMAC.hexdigest("SHA256", "meta-app-secret", body)

    {
      "CONTENT_TYPE" => "application/json",
      "X-Hub-Signature-256" => "sha256=#{signature}"
    }
  end

  def facebook_notification(
    page_id: "facebook-page-1",
    comment_id: "facebook-comment-1",
    author_id: "facebook-user-1",
    item: "comment",
    verb: "add"
  )
    {
      object: "page",
      entry: [
        {
          id: page_id,
          changes: [
            {
              field: "feed",
              value: {
                item:,
                verb:,
                comment_id:,
                post_id: "facebook-post-1",
                message: "Mẫu này còn hàng không?",
                from: { id: author_id, name: "Khách" }
              }
            }
          ]
        }
      ]
    }
  end

  def instagram_notification(
    account_id: "instagram-business-1",
    comment_id: "instagram-comment-1",
    author_id: "instagram-user-1",
    parent_id: nil
  )
    value = {
      id: comment_id,
      text: "Mẫu này còn hàng không?",
      from: { id: author_id, username: "khach" },
      self_ig_scoped_id: account_id,
      media: { id: "instagram-media-1", media_product_type: "FEED" }
    }
    value[:parent_id] = parent_id if parent_id

    {
      object: "instagram",
      entry: [
        {
          id: account_id,
          changes: [ { field: "comments", value: } ]
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
