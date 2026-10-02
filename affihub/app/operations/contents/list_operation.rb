# frozen_string_literal: true

class Contents::ListOperation < MainOperation
  attr_reader :product, :contents

  # @param params [Hash] :current_user and :product_id
  # @return [void]
  def initialize(params:)
    super
    @errors = ActiveModel::Errors.new(self)
    @product_id = params[:product_id]
  end

  # Loads a user's Product and its Content rows newest first.
  #
  # @return [void]
  def call
    @product = current_user&.products&.find_by(id: @product_id)
    @contents = @product ? @product.contents.order(created_at: :desc, id: :desc) : Content.none
  end
end
