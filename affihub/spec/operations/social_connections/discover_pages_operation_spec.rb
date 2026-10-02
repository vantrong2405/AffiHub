# frozen_string_literal: true

require "rails_helper"

RSpec.describe SocialConnections::DiscoverPagesOperation do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let(:connection) { create(:social_connection, user: user) }

  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  before { connection }

  it "returns real page metadata and caches only page ids and names for ten minutes" do
    stub_request(:get, "https://graph.facebook.com/v25.0/me/accounts")
      .with(query: hash_including("access_token" => connection.access_token))
      .to_return(status: 200, body: { data: [ { id: "page-1", name: "My Page", access_token: "must-not-cache" } ] }.to_json)

    operation = described_class.call(params: { current_user: user })

    expect(operation.success?).to eq(true)
    expect(operation.pages).to eq([ { "id" => "page-1", "name" => "My Page" } ])
    cache_key = "facebook_pages:#{connection.id}"
    expect(Rails.cache.read(cache_key)).to eq([ { "page_id" => "page-1", "name" => "My Page" } ])
    travel_to 9.minutes.from_now do
      expect(Rails.cache.read(cache_key)).to eq([ { "page_id" => "page-1", "name" => "My Page" } ])
    end
    travel_to 11.minutes.from_now do
      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end

  it "returns an empty list without creating a destination when no pages are managed" do
    stub_request(:get, "https://graph.facebook.com/v25.0/me/accounts")
      .with(query: hash_including("access_token" => connection.access_token))
      .to_return(status: 200, body: { data: [] }.to_json)

    operation = described_class.call(params: { current_user: user })

    expect(operation.pages).to eq([])
    expect(SocialDestination.count).to eq(0)
  end
end
