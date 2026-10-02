# frozen_string_literal: true

require "rails_helper"

RSpec.describe MetaGraphPublisher do
  let(:content) { create(:content, status: "approved", body: "Helpful product copy", affiliate_url: "https://affiliate.test/product") }
  let(:destination) { create(:social_destination) }
  let(:publication) { create(:publication, content: content, social_destination: destination) }
  let(:config) { Rails.application.config_for(:facebook) }

  it "publishes body plus affiliate URL and returns provider-confirmed result fields" do
    publish = stub_request(:post, "#{config.graph_url}/#{config.api_version}/#{destination.page_id}/feed")
      .with(body: hash_including("message" => "Helpful product copy\n\nhttps://affiliate.test/product"))
      .to_return(status: 200, body: { id: "page-1_post-1" }.to_json)
    stub_request(:get, "#{config.graph_url}/#{config.api_version}/page-1_post-1")
      .with(query: hash_including("fields" => config.permalink_fields))
      .to_return(status: 200, body: { permalink_url: "https://facebook.test/post/1" }.to_json)

    result = described_class.new.publish(publication)

    expect(result.success).to eq(true)
    expect(result.provider_post_id).to eq("page-1_post-1")
    expect(result.published_url).to eq("https://facebook.test/post/1")
    expect(result.published_at).to be_within(2.seconds).of(Time.current)
    expect(publish).to have_been_requested.once
  end

  it "returns success without a permalink when the permalink lookup fails" do
    stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/).to_return(status: 200, body: { id: "post-2" }.to_json)
    stub_request(:get, "#{config.graph_url}/#{config.api_version}/post-2")
      .with(query: hash_including("access_token" => destination.page_access_token))
      .to_return(status: 500, body: { error: { message: "temporarily unavailable", code: 1 } }.to_json)

    result = described_class.new.publish(publication)

    expect(result.success).to eq(true)
    expect(result.provider_post_id).to eq("post-2")
    expect(result.published_url).to be_nil
    expect(result.provider_metadata).to eq("permalink_fetch_failed" => true)
  end

  it "maps a structured Meta error response to a failed result" do
    stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/)
      .to_return(status: 400, body: { error: { message: "Permission denied", code: 200, fbtrace_id: "trace-1" } }.to_json)

    result = described_class.new.publish(publication)

    expect(result.success).to eq(false)
    expect(result.error_code).to eq("200")
    expect(result.error_message).to eq("Permission denied")
    expect(result.provider_metadata).to eq("fbtrace_id" => "trace-1")
  end
end
