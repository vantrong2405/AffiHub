# frozen_string_literal: true

class SessionsController < MainController
  def new
  end

  def create
    operator = Sessions::AuthenticateOperation.call(params: params.to_unsafe_h.merge(session: session))
    render_operation(operator, success: root_path, notice: "Logged in successfully")
  end

  def destroy
    session.delete(:user_id)
    redirect_to login_path, notice: "Logged out"
  end
end
