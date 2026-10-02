# frozen_string_literal: true

class Products::ListOperation < MainOperation
  attr_reader :products

  # @param params [Hash] :current_user and optional catalog filters
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
  end

  # Returns ranked products matching the current user's requested catalog filters.
  #
  # @return [ActiveRecord::Relation<Product>] current user's filtered products
  def call
    @products = current_user.products.filter_by(
      params.slice(:category, :min_price, :max_price, :min_rating, :min_discount)
    ).ranked
  end
end
