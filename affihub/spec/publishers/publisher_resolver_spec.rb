# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublisherResolver do
  it "resolves a Facebook Page destination to MetaGraphPublisher" do
    destination = create(:social_destination)

    expect(described_class.resolve(destination)).to eq(MetaGraphPublisher)
  end

  it "raises an explicit error for an unsupported provider and destination type" do
    destination = create(:social_destination, destination_type: "profile")

    expect { described_class.resolve(destination) }.to raise_error(KeyError, /facebook.*profile/)
  end
end
