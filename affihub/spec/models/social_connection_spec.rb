# frozen_string_literal: true

require "rails_helper"

RSpec.describe SocialConnection, type: :model do
  subject(:social_connection) { build(:social_connection) }

  it "returns true for valid? with a user and required attributes" do
    expect(social_connection.valid?).to eq(true)
  end

  it "belongs to a user" do
    expect(SocialConnection.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "returns 'facebook' for provider" do
    expect(social_connection.provider).to eq("facebook")
  end

  it "returns false for valid? when (user_id, provider) is already taken" do
    user = create(:user)
    create(:social_connection, user: user, provider: "facebook")
    duplicate = build(:social_connection, user: user, provider: "facebook")

    expect(duplicate.valid?).to eq(false)
  end

  it "stores access_token as ciphertext in the database" do
    social_connection.save!

    raw_value = SocialConnection.connection.select_value(
      "SELECT access_token FROM social_connections WHERE id = #{social_connection.id}"
    )

    expect(raw_value).not_to eq("social-token-value")
  end

  it "returns the decrypted access_token through the model" do
    social_connection.save!
    social_connection.reload

    expect(social_connection.access_token).to eq("social-token-value")
  end
end
