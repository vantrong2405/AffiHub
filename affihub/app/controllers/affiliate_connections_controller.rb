# frozen_string_literal: true

class AffiliateConnectionsController < MainController
  before_action :require_login

  # Renders the ACCESSTRADE API token form.
  #
  # @return [void]
  def new
    @form = AffiliateConnections::CreateForm.new
  end

  # Creates or updates the current user's ACCESSTRADE connection through its Operation.
  #
  # @return [void]
  def create
    operator = AffiliateConnections::CreateOperation.call(
      params: affiliate_connection_params.to_h.symbolize_keys.merge(current_user: current_user)
    )
    @form = operator.form
    render_operation(operator, success: new_affiliate_connection_path, failure: :new, notice: "ACCESSTRADE API token saved")
  end

  private

  # Permits only the API token used to connect ACCESSTRADE.
  #
  # @return [ActionController::Parameters] permitted connection attributes
  def affiliate_connection_params
    params.require(:affiliate_connection).permit(:api_key)
  end
end
