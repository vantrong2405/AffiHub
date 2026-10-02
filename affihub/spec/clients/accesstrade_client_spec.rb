# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccesstradeClient do
  subject(:client) { described_class.new }

  describe "#create_affiliate_links" do
    it "returns mapped affiliate links after POSTing configured campaign details" do
      config = Rails.application.config_for(:accesstrade)
      endpoint = URI.join(config.base_url, config.link_path).to_s
      url = "https://shopee.vn/product-a"

      stub_request(:post, endpoint)
        .with(
          headers: { "Authorization" => "Token accesstrade-token", "Content-Type" => "application/json" },
          body: {
            campaign_id: config.campaign_id,
            urls: [ url ],
            utm_source: config.utm_source
          }.to_json
        )
        .to_return(
          status: 200,
          body: {
            data: {
              success_link: [ { url_origin: url, aff_link: "https://accesstrade.vn/aff-a", short_link: "https://s.net/a" } ],
              error_link: [],
              suspend_url: []
            }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      expect(client.create_affiliate_links(urls: [ url ], token: "accesstrade-token")).to eq(
        url => { "aff_link" => "https://accesstrade.vn/aff-a", "short_link" => "https://s.net/a" }
      )
    end

    it "sends the request to the configured endpoint through the shared transport with configured timeouts" do
      config = Rails.application.config_for(:accesstrade)
      endpoint = URI.join(config.base_url, config.link_path)

      expect(Net::HTTP).to receive(:start).with(
        endpoint.host,
        endpoint.port,
        use_ssl: endpoint.scheme == "https",
        open_timeout: config.timeout,
        read_timeout: config.timeout,
        write_timeout: config.timeout
      ).and_call_original

      stub_request(:post, endpoint.to_s)
        .to_return(status: 200, body: { data: { success_link: [], error_link: [], suspend_url: [] } }.to_json)

      client.create_affiliate_links(urls: [ "https://shopee.vn/product-a" ], token: "accesstrade-token")
    end

    it "returns links for every URL after batching and mapping by url_origin regardless of response order" do
      config = Rails.application.config_for(:accesstrade)
      endpoint = URI.join(config.base_url, config.link_path).to_s
      urls = (1..(config.batch_size + 1)).map { |index| "https://shopee.vn/product-#{index}" }
      [ urls.first(config.batch_size), urls.last(1) ].each do |batch|
        stub_request(:post, endpoint)
          .with { |request| JSON.parse(request.body).fetch("urls") == batch }
          .to_return(
            status: 200,
            body: {
              data: {
                success_link: batch.reverse.map do |url|
                  { url_origin: url, aff_link: "https://accesstrade.vn/#{url.split('-').last}", short_link: "https://s.net/#{url.split('-').last}" }
                end,
                error_link: [],
                suspend_url: []
              }
            }.to_json
          )
      end

      result = client.create_affiliate_links(urls: urls, token: "accesstrade-token")

      expect(result).to eq(
        urls.to_h do |url|
          slug = url.split("-").last
          [ url, { "aff_link" => "https://accesstrade.vn/#{slug}", "short_link" => "https://s.net/#{slug}" } ]
        end
      )
      expect(a_request(:post, endpoint)).to have_been_made.twice
    end

    it "returns affiliate links after retrying a transient HTTP failure with configured backoff" do
      config = Rails.application.config_for(:accesstrade)
      endpoint = URI.join(config.base_url, config.link_path).to_s
      url = "https://shopee.vn/product-retry"
      stub_request(:post, endpoint)
        .to_return(
          { status: 503, body: "temporarily unavailable" },
          { status: 200, body: { data: { success_link: [ { url_origin: url, aff_link: "https://accesstrade.vn/retry", short_link: "https://s.net/retry" } ] } }.to_json }
        )

      result = client.create_affiliate_links(urls: [ url ], token: "accesstrade-token")

      expect(result).to eq(url => { "aff_link" => "https://accesstrade.vn/retry", "short_link" => "https://s.net/retry" })
      expect(a_request(:post, endpoint)).to have_been_made.twice
    end
  end
end
