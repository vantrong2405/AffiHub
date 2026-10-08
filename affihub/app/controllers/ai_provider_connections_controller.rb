class AiProviderConnectionsController < MainController
  # Lists supported AI sign-in choices and saved provider accounts.
  #
  # @return [ActionController::Metal::Response] the account list response
  def index
    service = AiProviderConnections::IndexService.new(current_origin: request.base_url)
    service.call
    @ai_provider_connections = service.ai_provider_connections
    @provider_options = service.provider_options
  end

  # Shows a saved AI account and its available model choices.
  #
  # @return [ActionController::Metal::Response] the account details response
  def show
    service = AiProviderConnections::ShowService.new(
      ai_provider_connection_id: params[:id],
      current_origin: request.base_url
    )
    service.call
    return render_service(service, failure_redirect: ai_provider_connections_path) unless service.success?

    @ai_provider_connection = service.ai_provider_connection
    @callback_origin = service.callback_origin
    @callback_origin_matches = service.callback_origin_matches
  end

  # Starts the selected provider's OAuth authorization flow.
  #
  # @return [ActionController::Metal::Response] the OAuth redirect response
  def create
    service = AiProviderConnections::CreateService.new(
      provider: params[:provider],
      session:,
      ai_provider_connection_id: params[:ai_provider_connection_id],
      request_origin: request.base_url
    )
    service.call
    render_service(service, failure_redirect: ai_provider_connections_path, allow_other_host: true) do
      service.authorization_url
    end
  end

  # Saves a model selected from the account's verified provider catalog.
  #
  # @return [ActionController::Metal::Response] the model selection response
  def update
    service = AiProviderConnections::UpdateService.new(
      ai_provider_connection_id: params[:id],
      selected_model: params.dig(:ai_provider_connection, :selected_model)
    )
    service.call
    render_service(
      service,
      failure_redirect: ai_provider_connection_path(params[:id]),
      notice: "Đã cập nhật model cho tài khoản AI."
    ) { ai_provider_connection_path(params[:id]) }
  end

  # Removes local tokens and attempts to revoke the provider's renewable session.
  #
  # @return [ActionController::Metal::Response] the disconnection response
  def destroy
    service = AiProviderConnections::DestroyService.new(ai_provider_connection_id: params[:id])
    service.call
    notice = if service.remote_revocation_confirmed
      "Đã ngắt kết nối và thu hồi phiên AI."
    else
      "Đã xóa token trên máy này; nhà cung cấp chưa xác nhận thu hồi phiên từ xa."
    end
    render_service(service, failure_redirect: ai_provider_connections_path, notice:) do
      ai_provider_connections_path
    end
  end
end
