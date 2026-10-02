# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FacebookPages", type: :request do
  let(:user) { create(:user) }
  let!(:connection) { create(:social_connection, user: user, access_token: "long-user-token") }

  before { post "/login", params: { email: user.email, password: "password123" } }

  it "discovers current Pages and renders an empty collection without creating destinations" do
    stub_request(:get, "https://graph.facebook.com/v25.0/me/accounts")
      .with(query: hash_including("access_token" => connection.access_token))
      .to_return(status: 200, body: { data: [] }.to_json)

    get "/facebook_pages"

    expect(response).to have_http_status(:ok)
    expect(SocialDestination.count).to eq(0)
  end

  it "syncs a selected discovered Page and redirects to its list" do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    Rails.cache.write("facebook_pages:#{connection.id}", [ { "page_id" => "page-1", "name" => "My Page" } ], expires_in: 10.minutes)
    stub_request(:get, "https://graph.facebook.com/v25.0/page-1")
      .with(query: hash_including("fields" => "access_token", "access_token" => connection.access_token))
      .to_return(status: 200, body: { access_token: "fresh-page-token" }.to_json)

    post "/facebook_pages/sync", params: { page_id: "page-1" }

    expect(response).to redirect_to(facebook_pages_path)
    expect(connection.social_destinations.find_by!(page_id: "page-1")).to have_attributes(name: "My Page", page_access_token: "fresh-page-token")
  end
end
