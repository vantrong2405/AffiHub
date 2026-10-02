# frozen_string_literal: true

class DashboardController < MainController
  before_action :require_login

  # Displays connection status and the current user's recent Publications.
  #
  # @return [void]
  def show
    operator = Dashboard::BuildStatusOperation.call(params: { current_user: current_user })
    return render_operation(operator, success: root_path, failure: :show) if operator.error?

    @ai_connection = operator.ai_connection
    @affiliate_connection = operator.affiliate_connection
    @social_connection = operator.social_connection
    @recent_publications = operator.recent_publications
  end
end
