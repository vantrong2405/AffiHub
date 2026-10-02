# frozen_string_literal: true

class PublicationsController < MainController
  before_action :require_login

  # Renders the form with only approved owned Content and owned Page destinations.
  #
  # @return [void]
  def new
    load_form_options
    @selected_content_id = params[:content_id]
  end

  # Creates a draft Publication from approved content and a selected Page.
  #
  # @return [void]
  def create
    operator = Publications::CreateOperation.call(params: create_params.merge(current_user: current_user))
    load_form_options if operator.error?
    success_path = operator.publication ? publication_path(operator.publication) : new_publication_path
    render_operation(operator, success: success_path, failure: :new)
  end

  # Displays one Publication and its provider result for its owner.
  #
  # @return [void]
  def show
    @publication = Publications::ShowOperation.call(params: { current_user: current_user, id: params[:id] }).publication
    head :not_found unless @publication
  end

  # Claims the draft and enqueues an immediate publication job.
  #
  # @return [void]
  def post_now
    operator = Publications::PostNowOperation.call(params: { current_user: current_user, id: params[:id] })
    render_action_result(operator)
  end

  # Schedules an owned draft for background publication.
  #
  # @return [void]
  def schedule
    operator = Publications::ScheduleOperation.call(
      params: { current_user: current_user, id: params[:id], scheduled_at: params[:scheduled_at] }
    )
    render_action_result(operator)
  end

  # Retries a failed or stale publication after any required duplicate-risk confirmation.
  #
  # @return [void]
  def retry
    operator = Publications::RetryOperation.call(
      params: { current_user: current_user, id: params[:id], confirm_duplicate_risk: params[:confirm_duplicate_risk] }
    )
    render_action_result(operator)
  end

  private

  # Loads form options through the read-only NewOperation.
  #
  # @return [void]
  def load_form_options
    operator = Publications::NewOperation.call(params: { current_user: current_user })
    @contents = operator.contents
    @destinations = operator.destinations
  end

  # Permits only the selected content and destination identifiers.
  #
  # @return [Hash] publication creation parameters
  def create_params
    params.permit(:content_id, :social_destination_id).to_h.symbolize_keys
  end

  # Renders the shared result while hiding Publication records not owned by this user.
  #
  # @param operator [MainOperation] result of a publication action
  # @return [void]
  def render_action_result(operator)
    return head(:not_found) unless operator.publication

    @publication = operator.publication
    render_operation(operator, success: publication_path(operator.publication), failure: :show)
  end
end
