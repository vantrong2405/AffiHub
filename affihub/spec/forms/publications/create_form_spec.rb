# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::CreateForm do
  let(:user) { create(:user) }
  let(:content) { create(:content, user: user, status: "approved") }
  let(:destination) { create(:social_destination, social_connection: create(:social_connection, user: user)) }

  it "accepts an approved Content and a destination owned by the current user" do
    form = described_class.new(current_user: user, content_id: content.id, social_destination_id: destination.id)

    expect(form.valid?).to eq(true)
  end

  it "rejects a Content that has not been approved" do
    content.update!(status: "review")
    form = described_class.new(current_user: user, content_id: content.id, social_destination_id: destination.id)

    expect(form.valid?).to eq(false)
  end

  it "rejects a missing destination and records belonging to another user" do
    other_content = create(:content, status: "approved")
    other_destination = create(:social_destination)

    expect(described_class.new(current_user: user, content_id: content.id).valid?).to eq(false)
    expect(described_class.new(current_user: user, content_id: other_content.id, social_destination_id: destination.id).valid?).to eq(false)
    expect(described_class.new(current_user: user, content_id: content.id, social_destination_id: other_destination.id).valid?).to eq(false)
  end
end
