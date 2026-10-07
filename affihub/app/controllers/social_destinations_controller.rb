class SocialDestinationsController < MainController
  # Saves the Facebook Page selected by the connected profile.
  def create
    service = SocialDestinations::CreateService.new(
      social_connection_id: params[:social_connection_id],
      external_id: params.dig(:social_destination, :external_id)
    )
    service.call
    render_service(service, failure: :new, notice: "Đã thêm Page làm đích đăng.") do
      social_connection_path(service.social_destination.social_connection_id)
    end
  end
end
