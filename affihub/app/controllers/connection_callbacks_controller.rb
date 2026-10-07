class ConnectionCallbacksController < MainController
  # Completes a provider callback using the state stored in the browser session.
  def show
    service = ConnectionCallbacks::ShowService.new(
      provider: params[:provider],
      params:,
      session:,
      callback_url: "#{request.base_url}#{request.path}"
    )
    service.call
    render_service(
      service,
      failure_redirect: social_connections_path,
      notice: "Tài khoản Facebook đã kết nối. Hãy chọn Page để đăng."
    ) do
      social_connection_social_destinations_path(service.social_connection)
    end
  end
end
