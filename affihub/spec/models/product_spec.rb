# frozen_string_literal: true

require "rails_helper"

RSpec.describe Product, type: :model do
  subject(:product) { build(:product) }

  it "belongs to a user" do
    expect(Product.reflect_on_association(:user)&.macro).to eq(:belongs_to)
  end

  it "is associated with the user's products" do
    expect(User.reflect_on_association(:products)&.macro).to eq(:has_many)
  end

  it "has the is_mall attribute" do
    expect(product.has_attribute?(:is_mall)).to eq(true)
  end

  it "allows separate users to own products with the same provider and URL" do
    first_user = create(:user)
    second_user = create(:user)

    first_product = create(:product, user: first_user, source_product_id: "first-source", original_product_url: "https://shopee.vn/product")
    second_product = create(:product, user: second_user, source_product_id: "second-source", original_product_url: "https://shopee.vn/product")

    expect([ first_product.user_id, second_product.user_id ]).to eq([ first_user.id, second_user.id ])
  end

  it "returns true for valid? with required attributes" do
    expect(product.valid?).to eq(true)
  end

  it "returns 'accesstrade' for affiliate_provider" do
    expect(product.affiliate_provider).to eq("accesstrade")
  end

  it "keeps the CSV source URL separate from the affiliate URL and leaves absent commission unset" do
    product.assign_attributes(
      original_product_url: "https://shopee.vn/source-product",
      affiliate_url: "https://accesstrade.vn/tracking-link",
      commission: nil
    )

    expect([ product.original_product_url, product.affiliate_url, product.commission ]).to eq(
      [ "https://shopee.vn/source-product", "https://accesstrade.vn/tracking-link", nil ]
    )
  end

  it "returns false for valid? when the same user imports the same provider URL twice" do
    owner = create(:user)
    create(:product, user: owner, affiliate_provider: "accesstrade", original_product_url: "https://shopee.vn/same")
    duplicate = build(:product, user: owner, affiliate_provider: "accesstrade", original_product_url: "https://shopee.vn/same")

    expect(duplicate.valid?).to eq(false)
  end

  it "returns true for valid? when the provider source ID is reused for a different URL" do
    create(:product, affiliate_provider: "accesstrade", source_product_id: "sp-1", original_product_url: "https://shopee.vn/first")
    other = build(:product, affiliate_provider: "accesstrade", source_product_id: "sp-1", original_product_url: "https://shopee.vn/second")

    expect(other.valid?).to eq(true)
  end

  describe ".filter_by" do
    it "returns only products matching category, price, rating, and discount filters" do
      owner = create(:user)
      matching = create(
        :product,
        user: owner,
        category: "A",
        price: 59_000,
        rating: 4.8,
        discount: 20,
        original_product_url: "https://shopee.vn/matching"
      )
      create(:product, user: owner, category: "B", price: 59_000, rating: 4.8, discount: 20, original_product_url: "https://shopee.vn/wrong-category")
      create(:product, user: owner, category: "A", price: 120_000, rating: 4.8, discount: 20, original_product_url: "https://shopee.vn/high-price")
      create(:product, user: owner, category: "A", price: 59_000, rating: 3.2, discount: 20, original_product_url: "https://shopee.vn/low-rating")
      create(:product, user: owner, category: "A", price: 59_000, rating: 4.8, discount: 5, original_product_url: "https://shopee.vn/low-discount")

      expect(Product.filter_by(category: "A", min_price: 50_000, max_price: 100_000, min_rating: 4.0, min_discount: 10)).to eq([ matching ])
    end
  end

  describe "#score" do
    it "returns the configured weighted sum using normalized product facts" do
      product.assign_attributes(sold: 10, rating: 4.5, is_mall: true, discount: 25)

      expect(product.score).to eq(685.0)
    end

    it "returns zero when every score fact is missing" do
      product.assign_attributes(sold: nil, rating: nil, is_mall: nil, discount: nil)

      expect(product.score).to eq(0.0)
    end
  end

  describe ".ranked" do
    it "returns products ordered by score, sync time, and ID in descending order" do
      owner = create(:user)
      shared_sync_time = Time.zone.local(2026, 10, 1, 12, 0, 0)
      old = create(:product, user: owner, sold: 100, rating: 4.0, is_mall: false, discount: 0,
                             last_synced_at: 1.day.ago, original_product_url: "https://shopee.vn/old")
      recent_first = create(:product, user: owner, sold: 100, rating: 4.0, is_mall: false, discount: 0,
                                      last_synced_at: shared_sync_time, original_product_url: "https://shopee.vn/recent-first")
      recent_second = create(:product, user: owner, sold: 100, rating: 4.0, is_mall: false, discount: 0,
                                       last_synced_at: shared_sync_time, original_product_url: "https://shopee.vn/recent-second")
      highest = create(:product, user: owner, sold: 101, rating: 4.0, is_mall: false, discount: 0,
                                 last_synced_at: 1.day.ago, original_product_url: "https://shopee.vn/highest")

      expect(Product.ranked.to_a).to eq([ highest, recent_second, recent_first, old ])
    end
  end
end
