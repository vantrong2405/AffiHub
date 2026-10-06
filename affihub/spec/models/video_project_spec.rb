# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoProject do
  describe "status lifecycle" do
    let(:video_project) { create(:video_project) }

    it "defaults to draft" do
      expect(video_project.status).to eq("draft")
    end

    it "persists each supported lifecycle status" do
      %w[draft processing ready failed].each do |status|
        video_project.update!(status:)

        expect(video_project.reload.status).to eq(status)
      end
    end
  end

  describe "source and render references" do
    let(:video_project) { create(:video_project) }
    let(:source_asset) { create(:source_asset, video_project:) }
    let(:render_version) { create(:render_version, source_asset:) }

    it "returns its source assets and render versions" do
      expect(video_project.source_assets).to eq([source_asset])
      expect(video_project.render_versions).to eq([render_version])
    end

    it "keeps a render version linked to its project and source asset" do
      expect(source_asset.video_project).to eq(video_project)
      expect(render_version.source_asset).to eq(source_asset)
    end
  end
end
