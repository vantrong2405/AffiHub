# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Publications", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:content) { create(:content, user: user, status: "approved", body: "Approved draft") }
  let(:destination) { create(:social_destination, social_connection: create(:social_connection, user: user)) }
  let(:publication) { create(:publication, content: content, social_destination: destination) }

  before { post "/login", params: { email: user.email, password: "password123" } }

  it "renders the creation form" do
    content
    destination

    get "/publications/new"

    expect(response).to have_http_status(:ok)
  end

  it "creates a draft Publication from approved owned content and a selected Page" do
    post "/publications", params: { content_id: content.id, social_destination_id: destination.id }

    expect(response).to have_http_status(:redirect)
    created = Publication.order(:id).last
    expect(response).to redirect_to(publication_path(created))
    expect(created).to have_attributes(content_id: content.id, social_destination_id: destination.id, status: "draft")
  end

  it "rejects creating a Publication when the Page is missing" do
    expect do
      post "/publications", params: { content_id: content.id }
    end.not_to change(Publication, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "shows a Publication only to its owner" do
    own_publication = publication
    foreign_publication = create(:publication)

    get "/publications/#{own_publication.id}"
    expect(response).to have_http_status(:ok)

    get "/publications/#{foreign_publication.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "claims Post Now once and enqueues the background job" do
    record = publication

    expect do
      post "/publications/#{record.id}/post_now"
      post "/publications/#{record.id}/post_now"
    end.to have_enqueued_job(PublishJob).once
    expect(record.reload.status).to eq("scheduled")
  end

  it "does not let another user claim a Publication" do
    record = publication
    other_user = create(:user)
    post "/login", params: { email: other_user.email, password: "password123" }

    expect do
      post "/publications/#{record.id}/post_now"
    end.not_to have_enqueued_job(PublishJob)
    expect(response).to have_http_status(:not_found)
    expect(record.reload.status).to eq("draft")
  end

  it "rejects a schedule in the past without enqueueing" do
    record = publication

    expect do
      post "/publications/#{record.id}/schedule", params: { scheduled_at: 1.hour.ago.iso8601 }
    end.not_to have_enqueued_job(PublishJob)
    expect(response).to have_http_status(:unprocessable_content)
    expect(record.reload.status).to eq("draft")
  end

  it "schedules an owned draft at the requested future time" do
    record = publication
    scheduled_at = 2.hours.from_now.change(usec: 0)

    expect do
      post "/publications/#{record.id}/schedule", params: { scheduled_at: scheduled_at.iso8601 }
    end.to have_enqueued_job(PublishJob).at(scheduled_at)
    expect(record.reload).to have_attributes(status: "scheduled", scheduled_at: scheduled_at)
  end

  it "retries a failed Publication and requires confirmation for ambiguous outcomes" do
    safe_failure = create(:publication, content: content, social_destination: destination, status: "failed", error_code: "200")
    ambiguous_failure = create(:publication, content: content, social_destination: destination, status: "failed", error_code: "internal_error")

    expect do
      post "/publications/#{safe_failure.id}/retry"
    end.to have_enqueued_job(PublishJob).once
    expect(safe_failure.reload.status).to eq("scheduled")

    expect do
      post "/publications/#{ambiguous_failure.id}/retry"
    end.not_to have_enqueued_job(PublishJob)
    expect(response).to have_http_status(:unprocessable_content)
    expect(ambiguous_failure.reload.status).to eq("failed")
  end

  it "retries stale Publishing only after explicit confirmation" do
    stale = create(:publication, content: content, social_destination: destination, status: "publishing", last_attempt_at: 20.minutes.ago)
    fresh = create(:publication, content: content, social_destination: destination, status: "publishing", last_attempt_at: 1.minute.ago)

    expect do
      post "/publications/#{stale.id}/retry", params: { confirm_duplicate_risk: "true" }
    end.to have_enqueued_job(PublishJob).once
    expect(stale.reload.status).to eq("scheduled")

    expect do
      post "/publications/#{fresh.id}/retry", params: { confirm_duplicate_risk: "true" }
    end.not_to have_enqueued_job(PublishJob)
    expect(fresh.reload.status).to eq("publishing")
  end
end
