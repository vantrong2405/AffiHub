# frozen_string_literal: true

class Products::ShowOperation < MainOperation
  attr_reader :product

  # @param params [Hash] :current_user and requested product :id
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
  end

  # Loads the requested product only from the current user's catalog.
  #
  # @return [Product, nil] owned product or nil when no owned product matches
  def call
    @product = current_user.products.find_by(id: params[:id])
  end
end
