# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::ScheduleOperation do
  include ActiveJob::TestHelper

  it "claims a draft and enqueues the job for the requested future time" do
    user = create(:user)
    publication = create(:publication, content: create(:content, user: user, status: "approved"))
    scheduled_at = 2.hours.from_now.change(usec: 0)

    expect do
      operation = described_class.call(params: { current_user: user, id: publication.id, scheduled_at: scheduled_at.iso8601 })
      expect(operation.success?).to eq(true)
    end.to have_enqueued_job(PublishJob).at(scheduled_at)
    expect(publication.reload).to have_attributes(status: "scheduled", scheduled_at: scheduled_at)
  end

  it "rejects past times without claiming or enqueueing" do
    user = create(:user)
    publication = create(:publication, content: create(:content, user: user, status: "approved"))

    expect do
      operation = described_class.call(params: { current_user: user, id: publication.id, scheduled_at: 1.hour.ago.iso8601 })
      expect(operation.success?).to eq(false)
    end.not_to have_enqueued_job(PublishJob)
    expect(publication.reload.status).to eq("draft")
  end
end
