# frozen_string_literal: true

require "rails_helper"

RSpec.describe AffiliateConnection, type: :model do
  subject(:affiliate_connection) { build(:affiliate_connection) }

  it "returns true for valid? with a user and required attributes" do
    expect(affiliate_connection.valid?).to eq(true)
  end

  it "belongs to a user" do
    expect(AffiliateConnection.reflect_on_association(:user).macro).to eq(:belongs_to)
  end

  it "returns 'accesstrade' for provider" do
    expect(affiliate_connection.provider).to eq("accesstrade")
  end

  it "stores api_key as ciphertext in the database" do
    affiliate_connection.save!

    raw_value = AffiliateConnection.connection.select_value(
      "SELECT api_key FROM affiliate_connections WHERE id = #{affiliate_connection.id}"
    )

    expect(raw_value).not_to eq("api-key-value")
  end

  it "returns the decrypted api_key through the model" do
    affiliate_connection.save!
    affiliate_connection.reload

    expect(affiliate_connection.api_key).to eq("api-key-value")
  end
end
