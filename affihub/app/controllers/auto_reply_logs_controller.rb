class AutoReplyLogsController < MainController
  # Loads comment events for the selected destination, or for all destinations.
  #
  # @return [ActionController::Metal::Response] the auto-reply log list response
  def index
    service = AutoReplyLogs::IndexService.new(social_destination_id: params[:social_destination_id])
    service.call
    @auto_reply_events = service.events
  end

  # Loads a comment event, its reply attempt, and append-only audit history.
  #
  # @return [ActionController::Metal::Response] the auto-reply log detail response
  def show
    head :not_found unless load_log_detail(params[:id])
  end

  # Records an operator decision for an unresolved Meta reply.
  #
  # @return [ActionController::Metal::Response] the auto-reply outcome response
  def update
    permitted_resolution = outcome_resolution_params
    service = AutoResponder::ResolveOutcomeService.new(
      auto_reply_event_id: params[:id],
      decision: permitted_resolution[:decision],
      evidence: permitted_resolution[:evidence],
      actor_reference: "local-operator",
      provider_reference: permitted_resolution[:provider_reference],
      risk_confirmed: permitted_resolution[:risk_confirmed] == "1"
    )
    service.call
    return head :not_found unless service.event

    @auto_reply_event = service.event
    unless service.success?
      return head :not_found unless load_log_detail(@auto_reply_event.id)

      @outcome_resolution_params = permitted_resolution
    end

    render_service(service, failure: :show, notice: "Đã lưu quyết định đối soát.") do
      auto_reply_log_path(@auto_reply_event)
    end
  end

  private

  def load_log_detail(event_id)
    service = AutoReplyLogs::ShowService.new(event_id:)
    return false unless service.call

    @auto_reply_event = service.event
    @outbound_attempt = service.outbound_attempt
    @audit_events = service.audit_events
    true
  end

  def outcome_resolution_params
    params.require(:outcome_resolution).permit(
      :decision,
      :evidence,
      :provider_reference,
      :risk_confirmed
    )
  end
end
