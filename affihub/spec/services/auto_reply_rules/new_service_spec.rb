require "rails_helper"

RSpec.describe AutoReplyRules::NewService, type: :service do
  describe "#call" do
    it "returns connected Facebook and Instagram destinations for the rule form" do
      facebook_destination = create(:social_destination, name: "Page Bếp Nhà")
      instagram_destination = create(
        :social_destination,
        social_connection: create(:social_connection, provider: "instagram"),
        provider: "instagram",
        name: "Instagram Bếp Nhà"
      )
      create(
        :social_destination,
        social_connection: create(:social_connection, provider: "youtube"),
        provider: "youtube",
        name: "Kênh Bếp Nhà"
      )
      create(:social_destination, status: "revoked", name: "Page đã ngắt kết nối")
      service = described_class.new

      expect(service.call).to eq(true)

      expect(service.destinations.map(&:id)).to eq([ facebook_destination.id, instagram_destination.id ])
    end

    it "returns a default rule with values from application configuration" do
      service = described_class.new

      expect(service.call).to eq(true)

      expect(service.rule).to have_attributes(rule_type: "default", enabled: true)
    end
  end
end
