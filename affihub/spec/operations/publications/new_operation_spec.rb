# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::NewOperation do
  it "returns only approved content and Page destinations owned by the current user" do
    user = create(:user)
    approved = create(:content, user: user, status: "approved")
    create(:content, user: user, status: "review")
    destination = create(:social_destination, social_connection: create(:social_connection, user: user))
    create(:social_destination)

    operation = described_class.call(params: { current_user: user })

    expect(operation.contents.map(&:id)).to eq([ approved.id ])
    expect(operation.destinations.map(&:id)).to eq([ destination.id ])
  end
end
