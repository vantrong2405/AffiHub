# frozen_string_literal: true

class AIConnectionsController < MainController
  before_action :require_login

  # Read-only: shows connection status, plan, and the Test Connection button.
  #
  # @return [void]
  def show
    operator = AIConnections::ShowOperation.call(params: params.to_unsafe_h.merge(current_user: current_user))
    @ai_connection = operator.ai_connection
  end

  # Binds the OAuth callback port and redirects to the real auth.openai.com consent screen.
  # Never redirects to authorize_url when the Operation fails (e.g. port already in use).
  #
  # @return [void]
  def connect
    operator = AIConnections::ConnectOperation.call(params: params.to_unsafe_h.merge(current_user: current_user))
    if operator.success?
      redirect_to operator.authorize_url, allow_other_host: true
    else
      flash[:alert] = operator.errors.full_messages.to_sentence
      redirect_to ai_connection_path
    end
  end

  # Plain relay — the real OAuth exchange already happened in CodexCallbackListener (a separate
  # process off the Puma request thread); this just turns its outcome/reason into user-facing
  # flash. No Operation to call here, so render_operation does not apply.
  #
  # @return [void]
  def callback_result
    if params[:outcome] == "success"
      flash[:notice] = "Codex connected successfully"
    else
      flash[:alert] = "Codex connection failed (#{params[:reason]})"
    end
    redirect_to ai_connection_path
  end

  # Sends a real prompt to Codex and surfaces the response via flash notice.
  #
  # @return [void]
  def test_connection
    operator = AIConnections::TestConnectionOperation.call(params: params.to_unsafe_h.merge(current_user: current_user))
    @ai_connection = AIConnections::ShowOperation.call(params: { current_user: current_user }).ai_connection
    render_operation(
      operator,
      success: ai_connection_path,
      failure: :show,
      notice: "Codex responded: #{operator.response&.dig("output_text")}"
    )
  end
end
