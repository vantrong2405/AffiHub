# frozen_string_literal: true

require "rails_helper"

RSpec.describe AIConnectionSerializer do
  let(:ai_connection) do
    create(:ai_connection, chatgpt_account_id: "secret-account-id", chatgpt_plan_type: "pro", id_token: "secret-id-token")
  end

  it "returns only the public status plan and connected_at fields" do
    hash = ActiveModelSerializers::SerializableResource.new(ai_connection).as_json

    expect(hash.keys).to eq(%i[status chatgpt_plan_type connected_at])
    expect(hash[:status]).to eq("connected")
    expect(hash[:chatgpt_plan_type]).to eq("pro")
    expect(hash[:connected_at]).to eq(ai_connection.connected_at)
    expect(hash.values).not_to include("secret-id-token", ai_connection.chatgpt_account_id)
  end
end
