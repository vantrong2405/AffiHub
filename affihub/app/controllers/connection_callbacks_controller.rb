class ConnectionCallbacksController < MainController
  # Completes a provider callback using the state stored in the browser session.
  #
  # @return [ActionController::Metal::Response] the callback redirect response
  def show
    return show_google_callback if params[:provider] == "google"

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

  private

  def show_google_callback
    service = GoogleConnections::CallbackService.new(
      params:,
      session:,
      callback_url: "#{request.base_url}#{request.path}"
    )
    service.call
    return render_service(service, failure_redirect: google_connections_path) unless service.success?

    render_service(
      service,
      success: google_connections_path,
      notice: "Đã kết nối Google #{service.google_connection.integration == "drive" ? "Drive" : "Sheets"}."
    )
  end
end
