# frozen_string_literal: true

require "rails_helper"

RSpec.describe SourceAsset do
  let(:source_asset) { create(:source_asset) }

  it "defaults to pending" do
    expect(source_asset.status).to eq("pending")
  end

  it "persists each supported processing status" do
    %w[pending processing ready failed].each do |status|
      source_asset.update!(status:)

      expect(source_asset.reload.status).to eq(status)
    end
  end
end
