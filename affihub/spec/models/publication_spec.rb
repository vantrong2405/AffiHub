# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publication, type: :model do
  it "belongs to Content and a concrete SocialDestination" do
    expect(described_class.reflect_on_association(:content).macro).to eq(:belongs_to)
    expect(described_class.reflect_on_association(:social_destination).macro).to eq(:belongs_to)
  end

  it "uses the shared publishing stale threshold" do
    expect(described_class::STALE_PUBLISHING_AFTER).to eq(10.minutes)
  end

  it "marks Publishing and internal errors as ambiguous but a structured Meta failure as safe" do
    expect(build(:publication, status: "publishing").ambiguous_outcome?).to eq(true)
    expect(build(:publication, status: "failed", error_code: "internal_error").ambiguous_outcome?).to eq(true)
    expect(build(:publication, status: "failed", error_code: "200").ambiguous_outcome?).to eq(false)
  end
end
