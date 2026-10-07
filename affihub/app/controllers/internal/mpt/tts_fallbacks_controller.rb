# frozen_string_literal: true

class Internal::Mpt::TtsFallbacksController < ActionController::API
  # Returns a saved or newly generated WAV to the authenticated MPT callback.
  #
  # @return [ActionController::Metal::Response] the WAV or a generic callback error
  def create
    service = AiGenerations::TtsFallbackCallbackService.new(
      raw_body: request.raw_post,
      timestamp: request.headers["X-MPT-Timestamp"],
      signature: request.headers["X-MPT-Signature"]
    )

    if service.call
      render body: service.audio_data, content_type: "audio/wav", status: :ok
    else
      render json: { error: "tts_fallback_unavailable" }, status: :unprocessable_content
    end
  end
end
