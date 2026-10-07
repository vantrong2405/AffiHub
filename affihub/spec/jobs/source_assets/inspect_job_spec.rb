require "rails_helper"

RSpec.describe SourceAssets::InspectJob, type: :job do
  describe "#perform" do
    let(:source_asset) { create(:source_asset) }
    let(:media_file) { File.open(Rails.root.join("spec/fixtures/files/local_source.mp4")) }

    before do
      source_asset.file.attach(io: media_file, filename: "local_source.mp4", content_type: "video/mp4")
    end

    after { media_file.close }

    it "returns a ready source after queued inspection" do
      described_class.perform_now(source_asset.id)

      expect(source_asset.reload.status).to eq("ready")
    end
  end
end
