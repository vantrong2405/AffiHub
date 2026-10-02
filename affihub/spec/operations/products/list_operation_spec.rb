# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::ListOperation do
  describe "#call" do
    it "returns only the current user's products" do
      user = create(:user)
      own_product = create(:product, user: user, original_product_url: "https://shopee.vn/own")
      create(:product, original_product_url: "https://shopee.vn/another-user")

      operation = described_class.call(params: { current_user: user })

      expect(operation.products).to eq([ own_product ])
    end

    it "returns the current user's products matching supplied filters" do
      user = create(:user)
      matching_product = create(:product, user: user, category: "A", rating: 4.8, price: 59_000,
                                         original_product_url: "https://shopee.vn/matching")
      create(:product, user: user, category: "B", rating: 4.8, price: 59_000,
                       original_product_url: "https://shopee.vn/other-category")
      create(:product, category: "A", rating: 4.8, price: 59_000,
                       original_product_url: "https://shopee.vn/other-user")

      operation = described_class.call(params: { current_user: user, category: "A", min_rating: "4.0" })

      expect(operation.products).to eq([ matching_product ])
    end
  end
end
