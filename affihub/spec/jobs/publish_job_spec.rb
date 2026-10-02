# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublishJob, type: :job do
  let(:user) { create(:user) }
  let(:content) { create(:content, user: user, status: "approved", body: "Post body") }
  let(:connection) { create(:social_connection, user: user) }
  let(:destination) { create(:social_destination, social_connection: connection) }
  let(:publication) { create(:publication, content: content, social_destination: destination, status: "scheduled") }
  let(:config) { Rails.application.config_for(:facebook) }

  it "claims only scheduled rows and no-ops for a non-scheduled Publication" do
    publication.update!(status: "draft")
    request = stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/)

    described_class.perform_now(publication.id)

    expect(publication.reload.status).to eq("draft")
    expect(request).not_to have_been_requested
  end

  it "publishes a scheduled Publication once and records the Meta response" do
    stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/).to_return(status: 200, body: { id: "page-1_post-1" }.to_json)
    stub_request(:get, "#{config.graph_url}/#{config.api_version}/page-1_post-1")
      .with(query: hash_including("access_token" => destination.page_access_token))
      .to_return(status: 200, body: { permalink_url: "https://facebook.test/post/1" }.to_json)

    described_class.perform_now(publication.id)
    described_class.perform_now(publication.id)

    expect(publication.reload).to have_attributes(status: "published", provider_post_id: "page-1_post-1", published_url: "https://facebook.test/post/1", attempt_count: 1)
  end

  it "records a structured Meta error as Failed and increments attempts" do
    stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/)
      .to_return(status: 400, body: { error: { message: "Permission denied", code: 200 } }.to_json)

    described_class.perform_now(publication.id)

    expect(publication.reload).to have_attributes(status: "failed", error_code: "200", error_message: "Permission denied", attempt_count: 1)
  end

  it "records ambiguous transport errors as internal_error and logs useful context" do
    request = stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/).to_timeout
    expect(Rails.logger).to receive(:error).with(
      /publication_id=#{publication.id}.*exception_class=MetaGraphClient::TransportError.*exception_message=.*backtrace=.*page_id=#{destination.page_id}/
    ) { expect(publication.reload.status).to eq("publishing") }

    described_class.perform_now(publication.id)

    expect(publication.reload).to have_attributes(status: "failed", error_code: "internal_error", attempt_count: 1)
    expect(request).to have_been_requested.once
  end

  it "converts any unexpected publisher exception to an ambiguous failure" do
    destination.update!(destination_type: "profile")

    described_class.perform_now(publication.id)

    expect(publication.reload).to have_attributes(status: "failed", error_code: "internal_error", attempt_count: 1)
  end

  it "sets last_attempt_at at the atomic claim" do
    stub_request(:post, /#{Regexp.escape(config.graph_url)}.*\/feed/).to_return(status: 200, body: { id: "post-3" }.to_json)
    stub_request(:get, /#{Regexp.escape(config.graph_url)}.*post-3/).to_return(status: 200, body: { permalink_url: "https://facebook.test/3" }.to_json)

    described_class.perform_now(publication.id)

    expect(publication.reload.last_attempt_at).to be_within(2.seconds).of(Time.current)
  end
end
