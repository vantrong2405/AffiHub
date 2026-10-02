# frozen_string_literal: true

class ContentsController < MainController
  before_action :require_login

  # Loads the selected Product and its content history for generation.
  #
  # @return [void]
  def new
    @product = Contents::ListOperation.call(params: { current_user: current_user, product_id: params[:product_id] }).product
    head :not_found unless @product
  end

  # Generates a new Content row from the selected Product.
  #
  # @return [void]
  def create
    operator = Contents::GenerateOperation.call(params: generate_params.merge(current_user: current_user))
    if operator.content
      @product = operator.content.product
    else
      @product = Contents::ListOperation.call(params: { current_user: current_user, product_id: params[:product_id] }).product
      return head(:not_found) unless @product
    end

    success_path = operator.content ? content_path(operator.content) : new_content_path(product_id: @product.id)
    render_operation(operator, success: success_path, failure: :new)
  end

  # Lists every Content row for one Product owned by the current user.
  #
  # @return [void]
  def index
    operator = Contents::ListOperation.call(params: { current_user: current_user, product_id: params[:product_id] })
    @product = operator.product
    @contents = operator.contents
    head :not_found unless @product
  end

  # Displays one Content row for review and its product facts.
  #
  # @return [void]
  def show
    @content = Contents::ShowOperation.call(params: { current_user: current_user, id: params[:id] }).content
    head :not_found unless @content
  end

  # Updates only the editable body of a review Content row.
  #
  # @return [void]
  def update
    operator = Contents::UpdateOperation.call(params: update_params.merge(current_user: current_user, id: params[:id]))
    @content = operator.content
    return head(:not_found) unless @content

    render_operation(operator, success: content_path(operator.content), failure: :show)
  end

  # Regenerates the selected Content row through the configured AI provider.
  #
  # @return [void]
  def regenerate
    operator = Contents::RegenerateOperation.call(params: { current_user: current_user, id: params[:id] })
    @content = operator.content
    return head(:not_found) unless @content

    render_operation(operator, success: content_path(operator.content), failure: :show)
  end

  # Approves the selected review Content row.
  #
  # @return [void]
  def approve
    transition(:approve)
  end

  # Rejects the selected review Content row.
  #
  # @return [void]
  def reject
    transition(:reject)
  end

  private

  # Permits the selected Product id and optional generation tone.
  #
  # @return [Hash] generation inputs
  def generate_params
    params.permit(:product_id, :tone).to_h.symbolize_keys
  end

  # Permits only editable Content fields.
  #
  # @return [Hash] body update input
  def update_params
    params.fetch(:content, ActionController::Parameters.new).permit(:body).to_h.symbolize_keys
  end

  # Performs one lifecycle transition and renders the common result.
  #
  # @param action [Symbol] supported transition
  # @return [void]
  def transition(action)
    operator = Contents::TransitionOperation.call(params: { current_user: current_user, id: params[:id], transition: action })
    @content = operator.content
    return head(:not_found) unless @content

    render_operation(operator, success: content_path(operator.content), failure: :show)
  end
end
