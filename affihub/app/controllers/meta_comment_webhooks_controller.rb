class MetaCommentWebhooksController < APIController
  skip_before_action :set_default_format
  skip_forgery_protection

  # Verifies Meta's callback handshake and returns its challenge when valid.
  #
  # @return [ActionController::Metal::Response] the handshake response
  def show
    service = MetaCommentWebhooks::VerifyService.new(
      mode: request.query_parameters["hub.mode"],
      verify_token: request.query_parameters["hub.verify_token"],
      challenge: request.query_parameters["hub.challenge"]
    )
    return render plain: service.challenge, content_type: "text/plain", status: :ok if service.call

    head :forbidden
  end

  # Verifies a signed Meta notification and acknowledges its delivery status.
  #
  # @return [ActionController::Metal::Response] the webhook acknowledgement
  def create
    service = MetaCommentWebhooks::ReceiveService.new(
      raw_body: request.raw_post,
      signature: request.headers["HTTP_X_HUB_SIGNATURE_256"]
    )
    service.call
    head service.http_status
  end
end
