# frozen_string_literal: true

require "rails_helper"

RSpec.describe AffiliateConnections::CreateForm, type: :model do
  it "returns true for valid? with an API token and without an API secret" do
    form = described_class.new(api_key: "accesstrade-token")

    expect(form.valid?).to eq(true)
  end

  it "returns false for valid? without an API token" do
    form = described_class.new(api_key: "")

    expect(form.valid?).to eq(false)
    expect(form.errors[:api_key]).to eq([ "can't be blank" ])
  end
end
