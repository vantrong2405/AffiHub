# frozen_string_literal: true

require "rails_helper"

RSpec.describe Publications::CreateOperation do
  it "creates a draft Publication for approved owned content and a selected Page" do
    user = create(:user)
    content = create(:content, user: user, status: "approved")
    destination = create(:social_destination, social_connection: create(:social_connection, user: user))

    expect do
      @operation = described_class.call(params: {
        current_user: user, content_id: content.id, social_destination_id: destination.id
      })
    end.to change(Publication, :count).by(1)

    expect(@operation.success?).to eq(true)
    expect(@operation.publication).to have_attributes(content_id: content.id, social_destination_id: destination.id, status: "draft")
  end
end
