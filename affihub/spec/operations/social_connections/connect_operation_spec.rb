# frozen_string_literal: true

require "rails_helper"

RSpec.describe SocialConnections::ConnectOperation do
  let(:user) { create(:user) }
  let(:callback_url) { "http://localhost:4000/social_connections/callback" }
  let(:config) { Rails.application.config_for(:facebook) }

  def stub_token_exchange(short_token:, long_token: "long-user-token")
    stub_request(:post, config.token_url)
      .to_return(status: 200, body: { access_token: short_token }.to_json)
    stub_request(:get, /#{Regexp.escape(config.token_url)}.*/)
      .with(query: hash_including("fb_exchange_token" => short_token))
      .to_return(status: 200, body: { access_token: long_token, expires_in: 5_184_000 }.to_json)
  end

  it "persists only the long-lived token after both exchanges succeed" do
    stub_token_exchange(short_token: "short-token")

    operation = described_class.call(params: { current_user: user, code: "oauth-code", redirect_uri: callback_url })

    expect(operation.success?).to eq(true)
    expect(user.social_connection).to have_attributes(provider: "facebook", access_token: "long-user-token")
  end

  it "does not persist a short-lived token when long-lived exchange fails" do
    stub_request(:post, config.token_url).to_return(status: 200, body: { access_token: "short-token" }.to_json)
    stub_request(:get, /#{Regexp.escape(config.token_url)}.*/)
      .to_return(status: 400, body: { error: { message: "invalid token", code: 190 } }.to_json)

    operation = described_class.call(params: { current_user: user, code: "oauth-code", redirect_uri: callback_url })

    expect(operation.success?).to eq(false)
    expect(user.social_connection).to be_nil
  end
end
