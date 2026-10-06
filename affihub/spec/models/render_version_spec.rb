# frozen_string_literal: true

require "rails_helper"

RSpec.describe RenderVersion do
  let(:render_version) { create(:render_version) }

  it "defaults to pending" do
    expect(render_version.status).to eq("pending")
  end

  it "persists each supported processing status" do
    %w[pending processing ready failed].each do |status|
      render_version.update!(status:)

      expect(render_version.reload.status).to eq(status)
    end
  end
end
