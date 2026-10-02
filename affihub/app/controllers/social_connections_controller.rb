# frozen_string_literal: true

class SocialConnectionsController < MainController
  before_action :require_login

  # Displays the current user's Facebook connection state.
  #
  # @return [void]
  def index
    @social_connection = SocialConnections::ShowOperation.call(params: { current_user: current_user }).social_connection
  end

  # Starts a standard Meta OAuth round-trip using the Rails session for state.
  #
  # @return [void]
  def connect
    state = SecureRandom.hex(16)
    session[:facebook_oauth_state] = state
    authorize_url = MetaGraphClient.new.build_authorize_url(state:, redirect_uri: social_connections_callback_url)
    redirect_to authorize_url, allow_other_host: true
  rescue KeyError
    session.delete(:facebook_oauth_state)
    redirect_to social_connections_path, alert: "Facebook Developer App credentials chưa được cấu hình."
  end

  # Validates and consumes OAuth state before exchanging the returned code.
  #
  # @return [void]
  def callback
    expected_state = session.delete(:facebook_oauth_state)
    unless valid_oauth_state?(expected_state, params[:state])
      return redirect_to social_connections_path, alert: "Facebook OAuth state không hợp lệ. Hãy thử kết nối lại."
    end

    if params[:error].present?
      return redirect_to social_connections_path, alert: "Bạn đã hủy kết nối Facebook."
    end
    return redirect_to social_connections_path, alert: "Facebook không trả authorization code. Hãy thử kết nối lại." if params[:code].blank?

    operator = SocialConnections::ConnectOperation.call(
      params: { current_user: current_user, code: params[:code], redirect_uri: social_connections_callback_url }
    )
    render_operation(
      operator,
      success: facebook_pages_path,
      failure: social_connections_path,
      notice: "Facebook connected successfully"
    )
  end

  private

  # Compares OAuth state in constant time when both values are present.
  #
  # @param expected_state [String, nil] state saved before redirecting to Meta
  # @param received_state [String, nil] state returned by Meta
  # @return [Boolean] whether the callback belongs to the active OAuth flow
  def valid_oauth_state?(expected_state, received_state)
    expected_state.present? && received_state.present? &&
      expected_state.bytesize == received_state.bytesize &&
      ActiveSupport::SecurityUtils.secure_compare(expected_state, received_state)
  end
end
