# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::ShowOperation do
  describe "#call" do
    it "returns the requested product when it belongs to the current user" do
      user = create(:user)
      product = create(:product, user: user, original_product_url: "https://shopee.vn/own")

      operation = described_class.call(params: { current_user: user, id: product.id })

      expect(operation.product).to eq(product)
    end

    it "returns nil when the requested product belongs to another user" do
      product = create(:product, original_product_url: "https://shopee.vn/another-user")
      user = create(:user)

      operation = described_class.call(params: { current_user: user, id: product.id })

      expect(operation.product).to be_nil
    end
  end
end
