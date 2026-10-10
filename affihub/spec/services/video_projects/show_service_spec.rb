require "rails_helper"

RSpec.describe VideoProjects::ShowService, type: :service do
  describe "#call" do
    let(:video_project) { create(:video_project) }
    let(:service) { described_class.new(video_project_id: video_project.id) }

    it "returns source assets that belong to the project" do
      source_asset = create(:source_asset, video_project:)
      create(:source_asset)

      service.call

      expect(service.source_assets).to eq([ source_asset ])
    end

    it "returns render versions that belong to the project" do
      render_version = create(:render_version, video_project:)
      create(:render_version)

      service.call

      expect(service.render_versions).to eq([ render_version ])
    end

    it "returns AI generations that belong to the project" do
      ai_generation = create(:ai_generation, video_project:)
      create(:ai_generation)

      service.call

      expect(service.ai_generations).to eq([ ai_generation ])
    end

    it "returns the newest AI generation first" do
      older_ai_generation = create(:ai_generation, video_project:, created_at: 2.days.ago)
      newer_ai_generation = create(:ai_generation, video_project:, created_at: 1.day.ago)

      service.call

      expect(service.ai_generations).to eq([ newer_ai_generation, older_ai_generation ])
    end
  end
end
