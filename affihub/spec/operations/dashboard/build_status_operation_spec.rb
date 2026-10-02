# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dashboard::BuildStatusOperation do
  it "returns the current user's connections and at most ten recent Publications" do
    user = create(:user)
    ai_connection = create(:ai_connection, user: user)
    affiliate_connection = create(:affiliate_connection, user: user)
    social_connection = create(:social_connection, user: user)
    destination = create(:social_destination, social_connection: social_connection)
    owned_publications = create_list(:publication, 12, social_destination: destination)

    other_user = create(:user)
    create(:ai_connection, user: other_user)
    create(:affiliate_connection, user: other_user)
    other_social_connection = create(:social_connection, user: other_user)
    create(:publication, social_destination: create(:social_destination, social_connection: other_social_connection))

    operation = described_class.call(params: { current_user: user })

    expect(operation.success?).to eq(true)
    expect(operation.ai_connection).to eq(ai_connection)
    expect(operation.affiliate_connection).to eq(affiliate_connection)
    expect(operation.social_connection).to eq(social_connection)
    expect(operation.recent_publications).to eq(owned_publications.sort_by(&:created_at).reverse.first(10))
    expect(operation.recent_publications).not_to include(Publication.joins(social_destination: :social_connection)
      .where(social_connections: { user_id: other_user.id }).first)
  end

  it "returns empty connection values and publications for a user with no activity" do
    operation = described_class.call(params: { current_user: create(:user) })

    expect(operation.success?).to eq(true)
    expect(operation.ai_connection).to be_nil
    expect(operation.affiliate_connection).to be_nil
    expect(operation.social_connection).to be_nil
    expect(operation.recent_publications).to eq([])
  end
end
