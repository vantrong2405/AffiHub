require "rails_helper"

RSpec.describe Publications::UpdateService, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version) }
    let(:social_destination) { create(:social_destination) }
    let(:publication) do
      create(
        :publication,
        render_version:,
        social_destination:,
        caption: "Caption ban đầu"
      )
    end

    it "updates the caption while keeping the draft render and destination" do
      service = described_class.new(publication_id: publication.id, caption: "Caption đã sửa")

      service.call

      expect(service).to be_success
      expect(publication.reload).to have_attributes(
        caption: "Caption đã sửa",
        render_version:,
        social_destination:
      )
    end

    context "when a publish attempt has already started" do
      let(:publication) do
        create(
          :publication,
          render_version:,
          social_destination:,
          caption: "Caption ban đầu",
          status: "uploading"
        )
      end

      it "returns failure and keeps the Publication unchanged" do
        service = described_class.new(publication_id: publication.id, caption: "Caption đã sửa")

        service.call

        expect(service).not_to be_success
        expect(publication.reload.caption).to eq("Caption ban đầu")
      end
    end
  end
end
