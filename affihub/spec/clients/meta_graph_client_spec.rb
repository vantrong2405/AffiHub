# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaGraphClient do
  let(:client) { described_class.new }
  let(:config) { Rails.application.config_for(:facebook) }

  it "builds an authorize URL with the configured Meta callback and requested state" do
    url = client.build_authorize_url(state: "state-123", redirect_uri: "http://localhost:4000/social_connections/callback")
    uri = URI(url)

    expect(uri.host).to eq("www.facebook.com")
    expect(uri.path).to eq("/#{config.api_version}/dialog/oauth")
    expect(URI.decode_www_form(uri.query).to_h).to eq(
      "client_id" => "test-facebook-app",
      "redirect_uri" => "http://localhost:4000/social_connections/callback",
      "scope" => config.permissions.join(","),
      "response_type" => "code",
      "state" => "state-123"
    )
  end

  it "exchanges an OAuth code using the configured token endpoint" do
    request = stub_request(:post, config.token_url)
      .with(body: hash_including("code" => "oauth-code", "client_id" => "test-facebook-app"))
      .to_return(status: 200, body: { access_token: "short-user-token", token_type: "bearer" }.to_json)

    expect(client.exchange_token(code: "oauth-code", redirect_uri: "http://localhost:4000/social_connections/callback")).to eq(
      "access_token" => "short-user-token", "token_type" => "bearer"
    )
    expect(request).to have_been_requested.once
  end

  it "exchanges a short-lived token for a long-lived token via the configured OAuth endpoint" do
    uri = URI(config.token_url)
    request = stub_request(:get, /#{Regexp.escape(uri.host)}#{Regexp.escape(uri.path)}/)
      .with(query: hash_including("grant_type" => "fb_exchange_token", "fb_exchange_token" => "short-user-token"))
      .to_return(status: 200, body: { access_token: "long-user-token", expires_in: 5_184_000 }.to_json)

    expect(client.exchange_long_lived_token(access_token: "short-user-token")).to eq(
      "access_token" => "long-user-token", "expires_in" => 5_184_000
    )
    expect(request).to have_been_requested.once
  end

  it "lists pages using the configured Graph API version" do
    endpoint = "#{config.graph_url}/#{config.api_version}/me/accounts"
    request = stub_request(:get, endpoint)
      .with(query: hash_including("fields" => "id,name,picture{url}", "access_token" => "user-token"))
      .to_return(status: 200, body: { data: [ { id: "page-1", name: "My Page", picture: { data: { url: "https://img.test/p.png" } } } ] }.to_json)

    expect(client.list_pages(access_token: "user-token").first).to eq(
      "id" => "page-1", "name" => "My Page", "picture" => { "data" => { "url" => "https://img.test/p.png" } }
    )
    expect(request).to have_been_requested.once
  end

  it "fetches a fresh Page token for the requested page through the configured API" do
    endpoint = "#{config.graph_url}/#{config.api_version}/page-1"
    request = stub_request(:get, endpoint)
      .with(query: hash_including("fields" => "access_token", "access_token" => "user-token"))
      .to_return(status: 200, body: { id: "page-1", access_token: "page-token" }.to_json)

    expect(client.fetch_page_token(page_id: "page-1", access_token: "user-token")).to eq("page-token")
    expect(request).to have_been_requested.once
  end

  it "publishes a text post to the configured Page feed endpoint" do
    endpoint = "#{config.graph_url}/#{config.api_version}/page-1/feed"
    request = stub_request(:post, endpoint)
      .with(body: hash_including("message" => "Copy\n\nhttps://affiliate.test", "access_token" => "page-token"))
      .to_return(status: 200, body: { id: "page-1_post-2" }.to_json)

    expect(client.publish_post(page_id: "page-1", page_access_token: "page-token", message: "Copy\n\nhttps://affiliate.test")).to eq("id" => "page-1_post-2")
    expect(request).to have_been_requested.once
  end

  it "fetches the post permalink from the configured Graph API endpoint" do
    endpoint = "#{config.graph_url}/#{config.api_version}/page-1_post-2"
    request = stub_request(:get, endpoint)
      .with(query: hash_including("fields" => "permalink_url", "access_token" => "page-token"))
      .to_return(status: 200, body: { id: "page-1_post-2", permalink_url: "https://facebook.test/post/2" }.to_json)

    expect(client.fetch_permalink_url(post_id: "page-1_post-2", page_access_token: "page-token")).to eq("https://facebook.test/post/2")
    expect(request).to have_been_requested.once
  end

  it "uses configured timeout values in the shared HTTP transport" do
    stub_request(:get, "#{config.graph_url}/#{config.api_version}/me/accounts")
      .with(query: hash_including("access_token" => "user-token"))
      .to_return(status: 200, body: { data: [] }.to_json)
    expect(Net::HTTP).to receive(:start).with(
      "graph.facebook.com",
      443,
      use_ssl: true,
      open_timeout: config.open_timeout,
      read_timeout: config.read_timeout,
      write_timeout: config.write_timeout
    ).and_call_original

    client.list_pages(access_token: "user-token")
  end
end
