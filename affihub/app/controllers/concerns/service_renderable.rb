# frozen_string_literal: true

module ServiceRenderable
  extend ActiveSupport::Concern

  # Redirects successful services and renders validation failures consistently.
  #
  # @param service [Object] completed service exposing +success?+ and +errors+
  # @param success [String, Hash, Proc] destination for a successful service
  # @param failure [Symbol, nil] optional template to render after validation fails
  # @param notice [String, nil] success message to store in the flash
  # @param alert [String, nil] optional error message to show instead of service errors
  # @return [ActionController::Metal::Response]
  def render_service(service, success:, failure: nil, notice: nil, alert: nil)
    if service.success?
      destination = success.respond_to?(:call) ? success.call : success
      redirect_to(destination, notice: notice)
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
