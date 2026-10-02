# frozen_string_literal: true

require "rails_helper"

RSpec.describe SocialDestination, type: :model do
  subject(:social_destination) { build(:social_destination) }

  it "returns true for valid? with a social_connection and required attributes" do
    expect(social_destination.valid?).to eq(true)
  end

  it "belongs to a social_connection" do
    expect(SocialDestination.reflect_on_association(:social_connection).macro).to eq(:belongs_to)
  end

  it "has many publications" do
    expect(SocialDestination.reflect_on_association(:publications).macro).to eq(:has_many)
  end

  it "returns 'page' for destination_type" do
    expect(social_destination.destination_type).to eq("page")
  end

  it "returns false for valid? when (social_connection_id, page_id) is already taken" do
    social_connection = create(:social_connection)
    create(:social_destination, social_connection: social_connection, page_id: "page-1")
    duplicate = build(:social_destination, social_connection: social_connection, page_id: "page-1")

    expect(duplicate.valid?).to eq(false)
  end

  it "stores page_access_token as ciphertext in the database" do
    social_destination.save!

    raw_value = SocialDestination.connection.select_value(
      "SELECT page_access_token FROM social_destinations WHERE id = #{social_destination.id}"
    )

    expect(raw_value).not_to eq("page-token-value")
  end

  it "returns the decrypted page_access_token through the model" do
    social_destination.save!
    social_destination.reload

    expect(social_destination.page_access_token).to eq("page-token-value")
  end
end
