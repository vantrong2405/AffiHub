class SocialDestinationsController < MainController
  # Shows Pages managed by the connected Facebook profile.
  #
  # @return [ActionController::Metal::Response] the Page selection response
  def index
    service = SocialDestinations::IndexService.new(social_connection_id: params[:social_connection_id])
    service.call
    return render_service(service, failure_redirect: social_connections_path) unless service.success?

    @social_connection = service.social_connection
    @available_pages = service.available_pages
  end

  # Saves Facebook Pages selected by the connected profile.
  #
  # @return [ActionController::Metal::Response] the Page selection result
  def create
    service = SocialDestinations::CreateService.new(
      social_connection_id: params[:social_connection_id],
      external_ids: params.dig(:social_destination, :external_ids)
    )
    service.call
    render_service(
      service,
      failure_redirect: social_connection_social_destinations_path(params[:social_connection_id]),
      notice: "Đã thêm Page làm đích đăng."
    ) do
      social_connection_path(service.social_connection)
    end
  end
end
