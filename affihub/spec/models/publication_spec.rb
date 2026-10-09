require "rails_helper"

RSpec.describe Publication, type: :model do
  describe "#status" do
    it "returns manual outcome not occurred when the operator confirms no post was created" do
      publication = build(:publication, status: "manual_outcome_not_occurred")

      expect(publication.status).to eq("manual_outcome_not_occurred")
    end
  end
end
