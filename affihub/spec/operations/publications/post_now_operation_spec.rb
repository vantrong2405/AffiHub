# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::PostNowOperation do
  include ActiveJob::TestHelper

  it "claims an owned draft atomically and enqueues one PublishJob" do
    user = create(:user)
    publication = create(:publication, content: create(:content, user: user, status: "approved"))

    expect do
      operation = described_class.call(params: { current_user: user, id: publication.id })
      expect(operation.success?).to eq(true)
    end.to have_enqueued_job(PublishJob).once
    expect(publication.reload.status).to eq("scheduled")
  end

  it "does not claim or enqueue a Publication owned by another user" do
    publication = create(:publication)

    expect do
      operation = described_class.call(params: { current_user: create(:user), id: publication.id })
      expect(operation.success?).to eq(false)
    end.not_to have_enqueued_job(PublishJob)
    expect(publication.reload.status).to eq("draft")
  end
end
