# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::RetryOperation do
  include ActiveJob::TestHelper

  it "retries a provider-confirmed failure without duplicate warning and keeps attempts" do
    user = create(:user)
    publication = create(:publication, content: create(:content, user: user, status: "approved"), status: "failed", attempt_count: 3, error_code: "200")

    expect do
      operation = described_class.call(params: { current_user: user, id: publication.id })
      expect(operation.success?).to eq(true)
    end.to have_enqueued_job(PublishJob).once
    expect(publication.reload).to have_attributes(status: "scheduled", attempt_count: 3)
  end

  it "requires explicit confirmation when the previous outcome is ambiguous" do
    user = create(:user)
    publication = create(:publication, content: create(:content, user: user, status: "approved"), status: "failed", error_code: "internal_error")

    expect do
      operation = described_class.call(params: { current_user: user, id: publication.id })
      expect(operation.success?).to eq(false)
    end.not_to have_enqueued_job(PublishJob)
    expect(publication.reload.status).to eq("failed")
  end

  it "retries stale Publishing only after confirmation and rejects fresh Publishing" do
    user = create(:user)
    stale = create(:publication, content: create(:content, user: user, status: "approved"), status: "publishing", last_attempt_at: 20.minutes.ago)
    fresh = create(:publication, content: create(:content, user: user, status: "approved"), status: "publishing", last_attempt_at: 1.minute.ago)

    expect do
      operation = described_class.call(params: { current_user: user, id: stale.id, confirm_duplicate_risk: "true" })
      expect(operation.success?).to eq(true)
    end.to have_enqueued_job(PublishJob).once
    expect(stale.reload.status).to eq("scheduled")

    expect do
      operation = described_class.call(params: { current_user: user, id: fresh.id, confirm_duplicate_risk: "true" })
      expect(operation.success?).to eq(false)
    end.not_to have_enqueued_job(PublishJob)
    expect(fresh.reload.status).to eq("publishing")
  end
end
