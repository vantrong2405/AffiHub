# frozen_string_literal: true

class Product < ApplicationRecord
  belongs_to :user
  has_many :contents

  SCORE_WEIGHTS = Rails.application.config_for(:product_catalog).score_weights

  validates :original_product_url, uniqueness: { scope: %i[user_id affiliate_provider] }, allow_nil: true

  # Filters products by the supplied category and numeric ranges.
  #
  # @param filters [Hash] optional category, min_price, max_price, min_rating, and min_discount values
  # @return [ActiveRecord::Relation<Product>] products matching all supplied filters
  scope :filter_by, lambda { |filters = {}|
    results = all
    results = results.where(category: filters[:category]) if filters[:category].present?
    results = results.where("price >= ?", filters[:min_price]) if filters[:min_price].present?
    results = results.where("price <= ?", filters[:max_price]) if filters[:max_price].present?
    results = results.where("rating >= ?", filters[:min_rating]) if filters[:min_rating].present?
    results = results.where("discount >= ?", filters[:min_discount]) if filters[:min_discount].present?
    results
  }

  # Ranks products by configured score, then most recent sync time and ID.
  #
  # @return [ActiveRecord::Relation<Product>] products in deterministic descending rank order
  scope :ranked, lambda {
    score_expression = sanitize_sql_array(
      [
        "(COALESCE(products.sold, 0) * ? + COALESCE(products.rating, 0) * ? + CASE WHEN products.is_mall THEN ? ELSE 0 END + COALESCE(products.discount, 0) * ?)",
        SCORE_WEIGHTS.fetch(:sold), SCORE_WEIGHTS.fetch(:rating), SCORE_WEIGHTS.fetch(:is_mall), SCORE_WEIGHTS.fetch(:discount)
      ]
    )
    order(Arel.sql("#{score_expression} DESC"), last_synced_at: :desc, id: :desc)
  }

  # Calculates the weighted sum of the product facts supplied by the catalog source.
  #
  # @return [Float] score using configured sold, rating, mall, and discount weights
  def score
    sold.to_f * SCORE_WEIGHTS.fetch(:sold).to_f +
      rating.to_f * SCORE_WEIGHTS.fetch(:rating).to_f +
      (is_mall? ? SCORE_WEIGHTS.fetch(:is_mall).to_f : 0) +
      discount.to_f * SCORE_WEIGHTS.fetch(:discount).to_f
  end
end
