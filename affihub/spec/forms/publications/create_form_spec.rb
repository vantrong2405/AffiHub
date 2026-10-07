require "rails_helper"

RSpec.describe Publications::CreateForm, type: :form do
  describe "#destination_captions_for_create" do
    it "returns captions only for selected destinations" do
      form = described_class.new(
        destination_ids: [ "12" ],
        destination_captions: { "12" => "Caption đã chọn", "34" => "Caption chưa chọn" }
      )

      expect(form.destination_captions_for_create).to eq("12" => "Caption đã chọn")
    end

    it "returns no captions when no destination is selected" do
      form = described_class.new(
        destination_ids: [],
        destination_captions: { "12" => "Caption chưa chọn" }
      )

      expect(form.destination_captions_for_create).to eq({})
    end
  end
end
