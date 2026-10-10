# frozen_string_literal: true

module ServiceRenderable
  extend ActiveSupport::Concern

  # Redirects successful services and renders validation failures consistently.
  #
  # @param service [Object] completed service exposing +success?+ and +errors+
  # @param success [String, Hash, nil] destination for a successful service
  # @param failure [Symbol, nil] optional template to render after validation fails
  # @param failure_redirect [String, Hash, nil] optional local destination for protocol failures
  # @param notice [String, nil] success message to store in the flash
  # @param alert [String, nil] optional error message to show instead of service errors
  # @param allow_other_host [Boolean] whether the success destination may be an OAuth provider
  # @yield Calculates the success destination only after the service succeeds
  # @yieldreturn [String, Hash] destination for a successful service
  # @return [ActionController::Metal::Response]
  def render_service(service, success: nil, failure: nil, failure_redirect: nil, notice: nil, alert: nil, allow_other_host: false, &success_block)
    if service.success?
      destination = success_block ? success_block.call : success
      redirect_to(destination, notice: notice, allow_other_host:)
    elsif failure_redirect
      redirect_to(failure_redirect, alert: alert || service.errors.full_messages.to_sentence)
    else
      flash.now[:alert] = alert || service.errors.full_messages.to_sentence
      render(failure || default_failure_action, status: :unprocessable_content)
    end
  end

  private

  # Chooses the conventional form template for the current command action.
  def default_failure_action
    case action_name
    when "create" then :new
    when "update" then :edit
    else action_name.to_sym
    end
  end
end
