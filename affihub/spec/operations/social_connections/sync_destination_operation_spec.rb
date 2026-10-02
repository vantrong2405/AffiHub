# frozen_string_literal: true

require "rails_helper"

RSpec.describe SocialConnections::SyncDestinationOperation do
  let(:user) { create(:user) }
  let(:connection) { create(:social_connection, user: user, access_token: "long-user-token") }

  around do |example|
    previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rails.cache = previous_cache
  end

  before do
    Rails.cache.write("facebook_pages:#{connection.id}", [ { "page_id" => "page-1", "name" => "My Page" } ], expires_in: 10.minutes)
  end

  it "fetches a fresh token and creates a destination for a recently discovered page" do
    stub_request(:get, "https://graph.facebook.com/v25.0/page-1")
      .with(query: hash_including("fields" => "access_token", "access_token" => "long-user-token"))
      .to_return(status: 200, body: { access_token: "fresh-page-token" }.to_json)

    operation = described_class.call(params: { current_user: user, page_id: "page-1" })

    expect(operation.success?).to eq(true)
    expect(operation.destination).to have_attributes(page_id: "page-1", name: "My Page", destination_type: "page", page_access_token: "fresh-page-token")
  end

  it "rejects a page id missing from discovery without calling Meta" do
    request = stub_request(:get, /graph.facebook.com/)

    operation = described_class.call(params: { current_user: user, page_id: "other-page" })

    expect(operation.success?).to eq(false)
    expect(SocialDestination.count).to eq(0)
    expect(request).not_to have_been_requested
  end
end
