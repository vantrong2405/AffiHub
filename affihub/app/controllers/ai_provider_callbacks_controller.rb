class AiProviderCallbacksController < MainController
  # Completes an AI provider callback using the state stored in the browser session.
  #
  # @return [ActionController::Metal::Response] the provider callback response
  def show
    service = AiProviderCallbacks::ShowService.new(
      params:,
      session:,
      callback_url: "#{request.base_url}#{request.path}"
    )
    service.call
    return render_service(service, failure_redirect: ai_provider_connections_path) unless service.success?

    connection = service.ai_provider_connection
    notice = connection_notice(connection, service.provider_configuration.fetch(:display_name))
    render_service(service, success: ai_provider_connection_path(connection), notice:)
  end

  private

  def connection_notice(connection, provider_name)
    if connection.scope_missing?
      return "Đã đăng nhập Google nhưng chưa cấp quyền #{provider_name}. Hãy kết nối lại và cấp quyền." if connection.provider == "gemini"

      return "Tài khoản AI chưa cấp quyền bắt buộc."
    end

    case connection.provider
    when "codex"
      "Đã xác thực tài khoản #{provider_name}. Quyền tạo nội dung chưa được xác minh; AffiHub chưa gửi yêu cầu model."
    when "gemini"
      "Đã kết nối #{provider_name}. Tài khoản đang chờ xác minh quyền và hạn mức trước khi tạo nội dung."
    else
      "Đã xác thực tài khoản AI."
    end
  end
end
