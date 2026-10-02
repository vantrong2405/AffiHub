# frozen_string_literal: true

class FacebookPagesController < MainController
  before_action :require_login

  # Discovers Facebook Pages for the current user's connection.
  #
  # @return [void]
  def index
    load_page_data
  end

  # Syncs one recently discovered Page as a SocialDestination.
  #
  # @return [void]
  def sync
    operator = SocialConnections::SyncDestinationOperation.call(
      params: { current_user: current_user, page_id: params[:page_id] }
    )
    load_page_data if operator.error?
    render_operation(operator, success: facebook_pages_path, failure: :index, notice: "Facebook Page saved")
  end

  private

  # Loads current Page discovery results and synced destination rows for rendering.
  #
  # @return [void]
  def load_page_data
    operator = SocialConnections::DiscoverPagesOperation.call(params: { current_user: current_user })
    @social_connection = operator.social_connection
    @pages = operator.pages || []
    flash.now[:alert] = operator.errors.full_messages.to_sentence if operator.error?
    @destinations = operator.destinations || {}
  end
end
