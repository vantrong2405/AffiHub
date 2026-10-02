# frozen_string_literal: true

require "rails_helper"

RSpec.describe AffiliateConnections::CreateOperation do
  let(:user) { create(:user) }

  it "creates an encrypted ACCESSTRADE connection for the current user" do
    operator = described_class.call(params: { current_user: user, api_key: "secret-token" })
    connection = AffiliateConnection.find_by!(user: user)

    expect(operator.success?).to eq(true)
    expect(connection.provider).to eq("accesstrade")
    expect(connection.api_key).to eq("secret-token")
    expect(connection.read_attribute_before_type_cast(:api_key)).not_to eq("secret-token")
  end
end
