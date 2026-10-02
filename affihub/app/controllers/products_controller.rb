# frozen_string_literal: true

class ProductsController < MainController
  before_action :require_login

  # Renders the current user's ranked product library with optional catalog filters.
  #
  # @return [void]
  def index
    @filters = product_filter_params
    @products = Products::ListOperation.call(params: @filters.merge(current_user: current_user)).products
  end

  # Renders one product only when it belongs to the current user.
  #
  # @return [void]
  def show
    @product = Products::ShowOperation.call(params: { current_user: current_user, id: params[:id] }).product
    head :not_found unless @product
  end

  # Imports a Dataminer CSV through the affiliate product import operation.
  #
  # @return [void]
  def import
    operator = AffiliateProducts::ImportOperation.call(
      params: import_params.merge(current_user: current_user)
    )
    @filters = product_filter_params
    @products = Products::ListOperation.call(params: @filters.merge(current_user: current_user)).products
    render_operation(
      operator,
      success: products_path,
      failure: :index,
      notice: "Imported #{operator.imported_count} products; #{operator.failed_count} failed"
    )
  end

  private

  # Permits the supported product catalog filters.
  #
  # @return [Hash{Symbol => String}] selected filters
  def product_filter_params
    params.permit(:category, :min_price, :max_price, :min_rating, :min_discount).to_h.symbolize_keys
  end

  # Permits the uploaded CSV file without accepting a user-provided path.
  #
  # @return [Hash{Symbol => ActionDispatch::Http::UploadedFile}] upload attributes
  def import_params
    file = params[:file]
    file ? { file: file } : {}
  end
end
