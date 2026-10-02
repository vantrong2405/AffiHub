# frozen_string_literal: true

require "rails_helper"

RSpec.describe AIConnections::RefreshTokenOperation do
  let(:ai_connection) { create(:ai_connection, refresh_token: "old-refresh-token", access_token: "old-access-token") }

  it "overwrites access_token/refresh_token and sets access_token_expires_at on success" do
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(
      status: 200,
      body: { access_token: "new-access-token", refresh_token: "new-refresh-token", expires_in: 3600 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    operator = described_class.call(params: { ai_connection: ai_connection })
    ai_connection.reload

    expect(operator.success?).to eq(true)
    expect(ai_connection.access_token).to eq("new-access-token")
    expect(ai_connection.refresh_token).to eq("new-refresh-token")
    expect(ai_connection.access_token_expires_at).to be_within(5.seconds).of(Time.current + 3600.seconds)
  end

  it "marks the AIConnection disconnected when the refresh_token has already been rotated/revoked" do
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 400, body: { error: "invalid_grant" }.to_json)

    operator = described_class.call(params: { ai_connection: ai_connection })
    ai_connection.reload

    expect(operator.success?).to eq(false)
    expect(ai_connection.status_disconnected?).to eq(true)
  end

  it "does not reuse a rotated refresh token when a stale connection copy needs refresh" do
    ai_connection.update!(access_token_expires_at: nil)
    stale_connection = AIConnection.find(ai_connection.id)
    refresh_request = stub_request(:post, "https://auth.openai.com/oauth/token")
      .with(body: hash_including("refresh_token" => "old-refresh-token"))
      .to_return(
        status: 200,
        body: { access_token: "new-access-token", refresh_token: "new-refresh-token", expires_in: 3600 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    ai_connection.ensure_fresh_token!
    stale_connection.ensure_fresh_token!
    ai_connection.reload

    expect(refresh_request).to have_been_requested.once
    expect(ai_connection.access_token).to eq("new-access-token")
    expect(ai_connection.refresh_token).to eq("new-refresh-token")
  end

  it "preserves credentials and connected status when refresh times out" do
    stub_request(:post, "https://auth.openai.com/oauth/token").to_timeout

    operator = described_class.call(params: { ai_connection: ai_connection })
    ai_connection.reload

    expect(operator.success?).to eq(false)
    expect(ai_connection.access_token).to eq("old-access-token")
    expect(ai_connection.refresh_token).to eq("old-refresh-token")
    expect(ai_connection.status).to eq("connected")
  end

  it "preserves credentials and connected status when the provider returns an unclassified error" do
    stub_request(:post, "https://auth.openai.com/oauth/token").to_return(status: 500, body: { error: "server_error" }.to_json)

    operator = described_class.call(params: { ai_connection: ai_connection })
    ai_connection.reload

    expect(operator.success?).to eq(false)
    expect(ai_connection.access_token).to eq("old-access-token")
    expect(ai_connection.refresh_token).to eq("old-refresh-token")
    expect(ai_connection.status).to eq("connected")
  end
end
