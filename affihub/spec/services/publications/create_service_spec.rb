require "rails_helper"

RSpec.describe Publications::CreateService, type: :service do
  describe "#call" do
    let(:render_version) { create(:render_version) }
    let(:first_destination) { create(:social_destination) }
    let(:second_destination) { create(:social_destination) }
    let(:checked_destination_ids) { [ first_destination.id, second_destination.id ] }
    let(:destination_results) do
      {
        first_destination.id.to_s => { "status" => "ready" },
        second_destination.id.to_s => { "status" => "ready" }
      }
    end
    let(:preflight_report) do
      create(
        :preflight_report,
        render_version:,
        checked_destination_ids:,
        destination_results:
      )
    end
    let(:destination_captions) do
      {
        first_destination.id => "Caption cho Page thứ nhất",
        second_destination.id => "Caption cho Page thứ hai"
      }
    end
    let(:service) do
      described_class.new(
        render_version_id: render_version.id,
        preflight_report_id: preflight_report.id,
        destination_captions:
      )
    end

    it "creates one draft with its own caption for each ready destination" do
      expect { service.call }.to change(Publication, :count).by(2)

      expect(service).to be_success
      expect(Publication.find_by!(social_destination: first_destination)).to have_attributes(
        render_version:,
        caption: "Caption cho Page thứ nhất",
        status: "draft"
      )
      expect(Publication.find_by!(social_destination: second_destination)).to have_attributes(
        render_version:,
        caption: "Caption cho Page thứ hai",
        status: "draft"
      )
    end

    context "when one selected destination is blocked by preflight" do
      let(:destination_results) do
        super().merge(second_destination.id.to_s => { "status" => "blocked" })
      end

      it "creates a draft only for the ready destination" do
        expect { service.call }.to change(Publication, :count).by(1)

        expect(service).to be_success
        expect(Publication.where(social_destination: first_destination).sole.caption)
          .to eq("Caption cho Page thứ nhất")
        expect(Publication.where(social_destination: second_destination)).to be_empty
      end
    end

    context "when the preflight report belongs to another render version" do
      let(:preflight_report) do
        create(
          :preflight_report,
          render_version: create(:render_version),
          checked_destination_ids:,
          destination_results:
        )
      end

      it "returns failure without creating publications" do
        expect { service.call }.not_to change(Publication, :count)

        expect(service).not_to be_success
      end
    end
  end
end
