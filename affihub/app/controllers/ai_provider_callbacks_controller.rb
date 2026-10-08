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
    notice = if connection.provider == "gemini"
      "Đã kết nối Gemini API. Tài khoản đang chờ xác minh quyền và hạn mức trước khi tạo nội dung."
    elsif connection.provider == "codex"
      "Đã xác thực tài khoản Codex. Quyền tạo nội dung chưa được xác minh; AffiHub chưa gửi yêu cầu model."
    elsif connection.scope_missing?
      "Đã đăng nhập ChatGPT nhưng tài khoản chưa cấp quyền sử dụng model."
    else
      "Đã kết nối tài khoản ChatGPT."
    end
    render_service(service, success: ai_provider_connection_path(connection), notice:)
  end
end
